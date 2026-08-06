{ pkgs, ... }:

let
  chatgptChromeExtension = pkgs.writeText "chatgpt-chrome-extension.json" ''
    {
      "external_update_url": "https://clients2.google.com/service/update2/crx"
    }
  '';
in
{
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
  };

  system.defaults = {
    dock = {
      autohide = true;
      autohide-delay = 0.0;
      minimize-to-application = false;
      show-recents = false;
      persistent-apps = [
        "/System/Applications/Music.app"
        "/Applications/Orion.app"
        "/Applications/1Password.app"
        "/Applications/Zed.app"
        "/Applications/Ghostty.app"
        "/System/Applications/Messages.app"
        "/System/Applications/Mail.app"
        "/System/Applications/Reminders.app"
        "/System/Applications/Calendar.app"
        "/System/Applications/System Settings.app"
        "/Applications/Signal.app"
        "Users/ncwade/Applications/Orion/WebApps/Kagi Assistant.app"
      ];
    };
    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      ShowPathbar = true;
    };
    screencapture = {
      disable-shadow = true;
      location = "~/Downloads";
      show-thumbnail = true;
      type = "png";
      target = "file";
    };
    SoftwareUpdate = {
      AutomaticallyInstallMacOSUpdates = true;
    };
  };
  system.startup = {
    chime = false;
  };

  system.activationScripts.postActivation.text = ''
    /usr/bin/install -d -o root -g wheel -m 0755 "/Library/Application Support/Google"
    /usr/bin/install -d -o root -g wheel -m 0755 "/Library/Application Support/Google/Chrome"
    /usr/bin/install -d -o root -g wheel -m 0755 "/Library/Application Support/Google/Chrome/External Extensions"
    /usr/bin/install -o root -g wheel -m 0644 \
      ${chatgptChromeExtension} \
      "/Library/Application Support/Google/Chrome/External Extensions/hehggadaopoacecdllhhajmbjkdcmajg.json"

    # Clean up the earlier defaults-based attempt; this is not a managed Mac.
    /usr/bin/defaults delete /Library/Preferences/com.google.Chrome ExtensionInstallForcelist 2>/dev/null || true
    launchctl asuser "$(id -u ncwade)" sudo --user=ncwade -- \
      /usr/bin/defaults delete com.google.Chrome ExtensionInstallForcelist 2>/dev/null || true
  '';
}
