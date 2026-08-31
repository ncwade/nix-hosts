{ ... }:

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
}
