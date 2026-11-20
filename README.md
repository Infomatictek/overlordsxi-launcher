# SoulspireXI Client Launcher

Distributable Windows client launcher (`SoulspireLauncher.exe`) for **SoulspireXI** servers, built with **C# / .NET 8 WPF** and **Ashita v4**.

## Features

- **Zero-Manual Setup**: Auto-detects an existing FINAL FANTASY XI installation from the Windows Registry and checks Windows DirectPlay and x86 VC++ prerequisites.
- **Automatic Tool Bootstrapping**: Downloads and configures **Ashita v4**, **`xiloader.exe`**, and **XIPivot** (`pivot.dll`) if missing.
- **SHA-256 Auto-Updater**: Uses [`manifest.json`](manifest.json) in this repository to keep the SoulspireXI DAT overlay (`dat-overlay/ROM`, `Call Eos`, `Call Titania`, WAR Commander active JAs `396`–`399` at display slots `908`–`911` — `Tactical Breach`, `Formation: Bulwark`, `Battle Cadence`, `Rallying Horn`, custom Job Traits `140`–`145`, & `Orphic Egg`) and Ashita v4 addons (`addons/ashita4/soulspire_talents`, `addons/ashita4/crystalsocket`) in sync with your game client. Whenever client DATs or addons change, run `python scripts/update-launcher-manifest.py` before pushing.
- **Graphics, Audio & Auto-Login**: Configures Ashita boot/registry settings (`config\boot\soulspirexi.ini`), XIPivot overlay (`config\pivot\soulspirexi.ini`), and startup script (`scripts\soulspirexi.txt` with `/addon load soulspire_talents`, `/addon load crystalsocket`, and `/fps`), plus optional Windows DPAPI-encrypted saved credentials.
- **Live Server Status & Easy Host Sharing**: Probes lobby (`54231`) and search (`54002`) TCP ports and loads an optional `soulspire-server.json` placed alongside `SoulspireLauncher.exe`.

## For Players

1. Ensure FINAL FANTASY XI is installed and patched, and Windows **DirectPlay** (*Turn Windows features on or off -> Legacy Components -> DirectPlay*) is enabled.
2. Download `SoulspireLauncher.exe` (or `SoulspireLauncher-win-x64.zip`) from the [Releases](https://github.com/Infomatictek/overlordsxi-launcher/releases) page.
3. Run `SoulspireLauncher.exe` and click **PLAY SOULSPIREXI**.
4. On first login, leave **Auto-login** unchecked to create your account inside the `xiloader` console.

## For Server Hosts

To distribute the launcher pre-configured for your server IP/hostname, place an `soulspire-server.json` file next to `SoulspireLauncher.exe` (you can generate one directly from **Graphics & Settings -> Export Shareable soulspire-server.json** inside the launcher):

```json
{
  "ServerName": "SoulspireXI",
  "DefaultHost": "play.your-server.example",
  "UseHairpin": true,
  "LobbyPort": 54231,
  "SearchPort": 54002
}
```

## Building From Source (Windows / .NET 8 SDK)

```powershell
dotnet test SoulspireLauncher.sln -c Release
dotnet publish SoulspireLauncher/SoulspireLauncher.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:PublishReadyToRun=true -o publish/SoulspireLauncher
```

Tagging `v*` (for example `v1.0.0`) runs [`.github/workflows/build-launcher.yml`](.github/workflows/build-launcher.yml) on `windows-latest`, runs unit tests, and publishes `SoulspireLauncher.exe` and `SoulspireLauncher-win-x64.zip` to GitHub Releases.
