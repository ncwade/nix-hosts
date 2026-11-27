# Headless Steam / Proton Gaming on Tycho (*Sea Power*)

`modules/nixos/gaming` enables Steam (Proton + 32-bit Vulkan RADV graphics),
`gamescope`, `.NET 8 SDK`, and an on-demand headless Sway + loopback-only
`wayvnc` session (`127.0.0.1:5900`) with no extra firewall ports opened.

## 1. Connect to a graphical Steam session from Luna

Start an interactive session on Tycho:

```sh
ssh -L 5900:127.0.0.1:5900 ncwade@tycho.tailf3d82.ts.net
tycho-gaming-session
```

From Luna, open Screen Sharing / VNC to `vnc://127.0.0.1:5900` (`open vnc://127.0.0.1:5900`), then launch `steam` inside the Sway terminal (`foot`) to complete Steam Guard login, enable **Steam Play / Proton** for all titles, and download **Sea Power: Naval Combat in the Missile Age** (AppID `1286220`).

## 2. Install BepInEx 5.4 and set the Proton DLL override

Once *Sea Power* is downloaded on Tycho:

```sh
seapower-install-bepinex
```

In Steam → *Sea Power* → **Properties → General → Launch Options**, set:

```sh
WINEDLLOVERRIDES="winhttp=n,b" %command%
```

Launch *Sea Power* once through Steam to initialize `BepInEx/` and `BepInEx/LogOutput.log`, then inspect the pinned `Assembly-CSharp.dll` from the `Wargaming` repository's `adapters/sea-power/scripts/inspect-assembly.fsx`.
