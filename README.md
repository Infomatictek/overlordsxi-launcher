# OverlordsXI Client Launcher

Distributable Windows client launcher (`OverlordsLauncher.exe`) for **OverlordsXI** servers, built with **C# / .NET 8 WPF** and **Ashita v4**.

## Features

- **Zero-Manual Setup**: Auto-detects an existing FINAL FANTASY XI installation from the Windows Registry and checks Windows DirectPlay and x86 VC++ prerequisites.
- **Automatic Tool Bootstrapping**: Downloads and configures **Ashita v4**, **`xiloader.exe`**, and **XIPivot** (`pivot.dll`) if missing.
- **SHA-256 Auto-Updater**: Fetches [`launcher/manifest.json`](https://raw.githubusercontent.com/Infomatictek/overlordsxi/main/launcher/manifest.json) from [`Infomatictek/overlordsxi`](https://github.com/Infomatictek/overlordsxi) and keeps the OverlordsXI DAT overlay (`Call Eos`, `Orphic Egg`) and `overlords_talents.lua` addon in sync.
- **Graphics, Audio & Auto-Login**: Configures Ashita boot/registry settings (`config\boot\overlordsxi.ini`), XIPivot overlay (`config\pivot\overlordsxi.ini`), and startup script (`scripts\overlordsxi.txt` with `/addon load overlords_talents` and `/fps`), plus optional Windows DPAPI-encrypted saved credentials.
- **Live Server Status & Easy Host Sharing**: Probes lobby (`54231`) and search (`54002`) TCP ports and loads an optional `overlords-server.json` placed alongside `OverlordsLauncher.exe`.

## For Players

1. Ensure FINAL FANTASY XI is installed and patched, and Windows **DirectPlay** (*Turn Windows features on or off -> Legacy Components -> DirectPlay*) is enabled.
2. Download `OverlordsLauncher.exe` (or `OverlordsLauncher-win-x64.zip`) from the [Releases](https://github.com/Infomatictek/overlordsxi-launcher/releases) page.
3. Run `OverlordsLauncher.exe` and click **PLAY OVERLORDSXI**.
4. On first login, leave **Auto-login** unchecked to create your account inside the `xiloader` console.

## For Server Hosts

To distribute the launcher pre-configured for your server IP/hostname, place an `overlords-server.json` file next to `OverlordsLauncher.exe` (you can generate one directly from **Graphics & Settings -> Export Shareable overlords-server.json** inside the launcher):

```json
{
  "ServerName": "OverlordsXI",
  "DefaultHost": "play.your-server.example",
  "UseHairpin": true,
  "LobbyPort": 54231,
  "SearchPort": 54002
}
```

## Building From Source (Windows / .NET 8 SDK)

```powershell
dotnet test OverlordsLauncher.sln -c Release
dotnet publish OverlordsLauncher/OverlordsLauncher.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:PublishReadyToRun=true -o publish/OverlordsLauncher
```

Tagging `v*` (for example `v1.0.0`) runs [`.github/workflows/build-launcher.yml`](.github/workflows/build-launcher.yml) on `windows-latest`, runs unit tests, and publishes `OverlordsLauncher.exe` and `OverlordsLauncher-win-x64.zip` to GitHub Releases.
