{ pkgs }:
let
  inherit (pkgs) lib;
  kindl = pkgs.python3Packages.buildPythonPackage {
    pname = "kindl";
    version = "0.1.0";
    pyproject = true;
    src = pkgs.fetchurl {
      name = "kindl-a896621.zip";
      url = "https://codeload.github.com/bGFiMTI2/kindl/zip/a896621dde52fc052a960f4bab7af84036013e23";
      hash = "sha256-qyCDdojMG7SS+0Kw/5uNxUR+6/625TrviYO3uwCIeL4=";
    };
    nativeBuildInputs = [ pkgs.unzip ];
    build-system = [ pkgs.python3Packages.hatchling ];
    dependencies = with pkgs.python3Packages; [ click cryptography httpx tabulate ];
    patches = [ ./kindle-kindl-hardening.patch ];
    pythonImportsCheck = [ "kindl.auth" "kindl.cli" "kindl.client" "kindl.pilot_guard" ];
    # These six offline checks work in the build sandbox. The two controlling
    # PTY tests are retained in the test file for a host with /dev/tty access.
    checkPhase = ''
      runHook preCheck
      export PYTHONPATH="$PWD/src''${PYTHONPATH:+:$PYTHONPATH}"
      ${pkgs.python3.interpreter} - <<'PY'
      import importlib.util, unittest
      spec = importlib.util.spec_from_file_location("runtime_tests", "${./kindle-runtime-tests.py}")
      module = importlib.util.module_from_spec(spec)
      spec.loader.exec_module(module)
      names = [name for name in unittest.defaultTestLoader.getTestCaseNames(module.GuardTests)
               if name not in ("test_long_hidden_callback_pty_preserves_all_4000_chars_and_restores_terminal",
                               "test_hidden_callback_interrupt_restores_terminal")]
      result = unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(module.GuardTests(name) for name in names))
      if not result.wasSuccessful(): raise SystemExit(1)
      PY
      runHook postCheck
    '';
    meta = {
      description = "Pinned Kindle client with private credential and destination guards";
      mainProgram = "kindl";
      platforms = lib.platforms.linux;
    };
  };
  dedrmSource = pkgs.fetchurl {
    url = "https://codeload.github.com/Satsuoni/DeDRM_tools/zip/b4cab04741b7b81e08fea65169af5480d1cea924";
    hash = "sha256-YeAfEWn9iQQGelemBEn0FfKeP2zeNz32NMHtmoZtFfg=";
  };
  dedrmPlugin = pkgs.runCommand "bookorbit-DeDRM-10.0.35.zip" {
    nativeBuildInputs = [ pkgs.unzip pkgs.patch pkgs.python3 ];
  } ''
    unzip -q ${dedrmSource}
    cd DeDRM_tools-*/DeDRM_plugin
    patch -p1 < ${./kindle-dedrm-hardening.patch}
    # Mirror only the reviewed compatibility-marker substitution from upstream
    # make_release.py; do not run its broader Windows-tool release packaging.
    python3 - "$out" <<'PY'
    from pathlib import Path
    import sys, zipfile
    root = Path.cwd()
    compat = (root / "__calibre_compat_code.py").read_bytes()
    with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(root.rglob("*")):
            if not path.is_file() or "__pycache__" in path.parts:
                continue
            data = path.read_bytes()
            if path.suffix == ".py":
                data = data.replace(b"#@@CALIBRE_COMPAT_CODE@@", compat)
            entry = zipfile.ZipInfo(str(path.relative_to(root)), (1980, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, data)
    PY
  '';
  kfxInputPlugin = pkgs.fetchurl {
    name = "KFX_Input-2.34.2.zip";
    url = "https://plugins.calibre-ebook.com/291290.zip";
    hash = "sha256-M4gJwY5fm7ch3DVwpkz2963UoXEcgYPmF56Q/LrfPB0=";
  };
  # Calibre and dependency versions are pinned by this repository's flake.lock.
  calibre = pkgs.calibre;
  initializeConfig = pkgs.writeShellApplication {
    name = "bookorbit-kindle-init-calibre";
    runtimeInputs = [ pkgs.python3 calibre ];
    text = ''
      umask 077
      export QT_QPA_PLATFORM=offscreen
      : "''${CALIBRE_CONFIG_DIRECTORY:?Set a private writable Calibre config directory}"
      python3 ${./kindle-runtime-init.py} "$CALIBRE_CONFIG_DIRECTORY"
      calibre-customize --add ${dedrmPlugin}
      calibre-customize --add ${kfxInputPlugin}
    '';
  };
in {
  inherit kindl calibre dedrmPlugin kfxInputPlugin initializeConfig;
  # Parent orchestration can import kindl directly using this interpreter.
  python = pkgs.python3.withPackages (_: [ kindl ]);
}
