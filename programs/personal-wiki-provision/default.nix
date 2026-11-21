{ writeShellApplication, coreutils, git, openssh, gh, jq }:
writeShellApplication {
  name = "personal-wiki-provision";
  runtimeInputs = [ coreutils git openssh gh jq ];
  text = builtins.readFile ./provision.sh;
}
