using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using SoulspireLauncher.Models;

namespace SoulspireLauncher.Services;

public sealed class SyncProgress
{
    public string Message { get; init; } = string.Empty;
    public double Percent { get; init; }
}

public sealed class ManifestUpdateService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly HttpClient _http;

    public ManifestUpdateService(HttpClient? httpClient = null)
    {
        _http = httpClient ?? CreateDefaultHttpClient();
    }

    public static HttpClient CreateDefaultHttpClient()
    {
        var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(60)
        };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("SoulspireLauncher/1.0 (+https://github.com/Infomatictek/overlordsxi-launcher)");
        client.DefaultRequestHeaders.CacheControl = new CacheControlHeaderValue
        {
            NoCache = true,
            NoStore = true
        };
        client.DefaultRequestHeaders.Pragma.ParseAdd("no-cache");
        return client;
    }

    public LauncherManifest LoadEmbeddedManifest()
    {
        var assembly = Assembly.GetExecutingAssembly();
        var resourceName = assembly.GetManifestResourceNames()
            .FirstOrDefault(n => n.EndsWith("manifest.json", StringComparison.OrdinalIgnoreCase));

        if (resourceName is null)
        {
            return new LauncherManifest();
        }

        using var stream = assembly.GetManifestResourceStream(resourceName);
        if (stream is null)
        {
            return new LauncherManifest();
        }

        return JsonSerializer.Deserialize<LauncherManifest>(stream, JsonOptions) ?? new LauncherManifest();
    }

    public async Task<(LauncherManifest Manifest, bool FromRemote)> FetchManifestAsync(
        LauncherManifest fallback,
        LocalServerOverride? localOverride,
        CancellationToken cancellationToken = default)
    {
        var manifest = fallback;
        var fromRemote = false;

        var rawBase = fallback.Repo.RawBaseUrl.TrimEnd('/');
        if (!string.IsNullOrWhiteSpace(rawBase))
        {
            string? pinnedRawBase = null;
            if (IsGitHubRawBaseUrl(rawBase) &&
                !string.IsNullOrWhiteSpace(fallback.Repo.Owner) &&
                !string.IsNullOrWhiteSpace(fallback.Repo.Name) &&
                !string.IsNullOrWhiteSpace(fallback.Repo.Branch))
            {
                var commitSha = await TryResolveBranchCommitShaAsync(
                    fallback.Repo.Owner.Trim(),
                    fallback.Repo.Name.Trim(),
                    fallback.Repo.Branch.Trim(),
                    cancellationToken).ConfigureAwait(false);
                if (!string.IsNullOrWhiteSpace(commitSha))
                {
                    pinnedRawBase = $"https://raw.githubusercontent.com/{fallback.Repo.Owner.Trim()}/{fallback.Repo.Name.Trim()}/{commitSha}";
                }
            }

            if (!string.IsNullOrWhiteSpace(pinnedRawBase))
            {
                var remote = await TryFetchManifestFromUrlAsync($"{pinnedRawBase}/manifest.json", cancellationToken)
                    .ConfigureAwait(false);
                if (remote is not null && remote.Files.Count > 0)
                {
                    remote.ResolvedRawBaseUrl = pinnedRawBase;
                    manifest = remote;
                    fromRemote = true;
                }
            }

            if (!fromRemote)
            {
                var url = $"{rawBase}/manifest.json?t={DateTimeOffset.UtcNow.ToUnixTimeSeconds()}";
                var remote = await TryFetchManifestFromUrlAsync(url, cancellationToken).ConfigureAwait(false);
                if (remote is not null && remote.Files.Count > 0)
                {
                    remote.ResolvedRawBaseUrl = rawBase;
                    manifest = remote;
                    fromRemote = true;
                }
            }
        }

        ApplyLocalOverride(manifest, localOverride);
        return (manifest, fromRemote);
    }

    public static bool IsGitHubRawBaseUrl(string rawBaseUrl) =>
        Uri.TryCreate(rawBaseUrl, UriKind.Absolute, out var uri) &&
        uri.Host.Equals("raw.githubusercontent.com", StringComparison.OrdinalIgnoreCase);

    private async Task<string?> TryResolveBranchCommitShaAsync(
        string owner,
        string repo,
        string branch,
        CancellationToken cancellationToken)
    {
        try
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            cts.CancelAfter(TimeSpan.FromSeconds(8));

            var apiUrl = $"https://api.github.com/repos/{Uri.EscapeDataString(owner)}/{Uri.EscapeDataString(repo)}/commits/{Uri.EscapeDataString(branch)}";
            using var request = new HttpRequestMessage(HttpMethod.Get, apiUrl);
            request.Headers.Accept.ParseAdd("application/vnd.github.sha");

            using var response = await _http.SendAsync(request, cts.Token).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                return null;
            }

            var sha = (await response.Content.ReadAsStringAsync(cts.Token).ConfigureAwait(false)).Trim();
            return sha.Length == 40 && sha.All(Uri.IsHexDigit) ? sha : null;
        }
        catch
        {
            return null;
        }
    }

    private async Task<LauncherManifest?> TryFetchManifestFromUrlAsync(string url, CancellationToken cancellationToken)
    {
        try
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            cts.CancelAfter(TimeSpan.FromSeconds(10));
            var json = await _http.GetStringAsync(url, cts.Token).ConfigureAwait(false);
            return JsonSerializer.Deserialize<LauncherManifest>(json, JsonOptions);
        }
        catch
        {
            return null;
        }
    }

    public static void ApplyLocalOverride(LauncherManifest manifest, LocalServerOverride? localOverride)
    {
        if (localOverride is null)
        {
            return;
        }

        if (!string.IsNullOrWhiteSpace(localOverride.ServerName))
        {
            manifest.ServerName = localOverride.ServerName.Trim();
        }

        if (!string.IsNullOrWhiteSpace(localOverride.DefaultHost))
        {
            manifest.DefaultHost = localOverride.DefaultHost.Trim();
        }

        if (localOverride.UseHairpin.HasValue)
        {
            manifest.UseHairpin = localOverride.UseHairpin.Value;
        }

        if (localOverride.LobbyPort is > 0)
        {
            manifest.Ports.Lobby = localOverride.LobbyPort.Value;
        }

        if (localOverride.AuthPort is > 0)
        {
            manifest.Ports.Auth = localOverride.AuthPort.Value;
        }

        if (localOverride.SearchPort is > 0)
        {
            manifest.Ports.Search = localOverride.SearchPort.Value;
        }
    }

    public static string ResolveTargetFilePath(LauncherSettings settings, ManifestFileEntry entry)
    {
        var relative = entry.TargetPath.Replace('/', Path.DirectorySeparatorChar);
        if (entry.Category.Equals("dat", StringComparison.OrdinalIgnoreCase))
        {
            return Path.Combine(settings.AshitaPath, "polplugins", "DATs", AshitaConfigGenerator.OverlayFolderName, relative);
        }

        if (entry.Category.Equals("plugin", StringComparison.OrdinalIgnoreCase))
        {
            return Path.Combine(settings.AshitaPath, "plugins", relative);
        }

        return Path.Combine(settings.AshitaPath, "addons", relative);
    }

    public List<ManifestFileEntry> GetOutdatedFiles(
        LauncherManifest manifest,
        LauncherSettings settings,
        bool forceAll = false)
    {
        var pending = new List<ManifestFileEntry>();
        foreach (var entry in manifest.Files)
        {
            var dest = ResolveTargetFilePath(settings, entry);
            if (forceAll || !FileMatchesHash(dest, entry.Sha256))
            {
                pending.Add(entry);
                continue;
            }

            if (entry.Category.Equals("dat", StringComparison.OrdinalIgnoreCase) &&
                settings.SyncToCustomDatFolder &&
                !string.IsNullOrWhiteSpace(settings.CustomDatOverlayPath))
            {
                var customDest = Path.Combine(settings.CustomDatOverlayPath, entry.TargetPath.Replace('/', Path.DirectorySeparatorChar));
                if (!FileMatchesHash(customDest, entry.Sha256))
                {
                    pending.Add(entry);
                }
            }
        }

        return pending;
    }

    // Addons retired or renamed during the OverlordsXI -> SoulspireXI transition.
    // Removing these prevents duplicate Ashita addon loads on upgraded installs.
    public static readonly string[] RetiredAddonFolders =
    {
        "overlords_boost",
        "overlords_talents",
        "overlords_gear",
        "overlords_soulhud",
        "overlords_soul_actions"
    };

    private static readonly string[] RetiredAddonFiles =
    {
        "metrics/overlords.lua"
    };

    public static void RemoveRetiredAddons(LauncherSettings settings)
    {
        foreach (var folder in RetiredAddonFolders)
        {
            try
            {
                var dir = Path.Combine(settings.AshitaPath, "addons", folder);
                if (Directory.Exists(dir))
                {
                    Directory.Delete(dir, recursive: true);
                }
            }
            catch (IOException)
            {
                // In use by a running client; it is removed on the next sync.
            }
            catch (UnauthorizedAccessException)
            {
            }
        }

        foreach (var relFile in RetiredAddonFiles)
        {
            try
            {
                var path = Path.Combine(settings.AshitaPath, "addons", relFile.Replace('/', Path.DirectorySeparatorChar));
                if (File.Exists(path))
                {
                    File.Delete(path);
                }
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }

    public async Task<int> SyncOverlordsFilesAsync(
        LauncherManifest manifest,
        LauncherSettings settings,
        bool forceAll,
        IProgress<SyncProgress>? progress = null,
        CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(settings.AshitaPath);
        RemoveRetiredAddons(settings);

        var pending = GetOutdatedFiles(manifest, settings, forceAll);
        if (pending.Count == 0)
        {
            progress?.Report(new SyncProgress { Message = "All SoulspireXI client files are up to date.", Percent = 100 });
            return 0;
        }

        var rawBase = (!string.IsNullOrWhiteSpace(manifest.ResolvedRawBaseUrl)
            ? manifest.ResolvedRawBaseUrl
            : manifest.Repo.RawBaseUrl).TrimEnd('/');
        var completed = 0;

        foreach (var entry in pending)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var pct = (double)completed / pending.Count * 100.0;
            progress?.Report(new SyncProgress
            {
                Message = $"Downloading {entry.TargetPath} ({completed + 1}/{pending.Count})...",
                Percent = pct
            });

            var destPath = ResolveTargetFilePath(settings, entry);
            var destDir = Path.GetDirectoryName(destPath)!;
            Directory.CreateDirectory(destDir);

            var cacheBuster = !string.IsNullOrWhiteSpace(entry.Sha256)
                ? $"sha={Uri.EscapeDataString(entry.Sha256)}"
                : $"t={DateTimeOffset.UtcNow.ToUnixTimeSeconds()}";
            var sourcePath = entry.SourcePath.TrimStart('/');
            var url = $"{rawBase}/{sourcePath}?{cacheBuster}";
            var tempPath = destPath + ".download";

            await DownloadFileAsync(url, tempPath, cancellationToken).ConfigureAwait(false);

            if (!string.IsNullOrWhiteSpace(entry.Sha256))
            {
                var actualHash = ComputeSha256(tempPath);
                if (!actualHash.Equals(entry.Sha256, StringComparison.OrdinalIgnoreCase))
                {
                    TryDeleteFile(tempPath);
                    var retryUrl = $"{rawBase}/{sourcePath}?cb={Guid.NewGuid():N}";
                    await DownloadFileAsync(retryUrl, tempPath, cancellationToken).ConfigureAwait(false);
                    actualHash = ComputeSha256(tempPath);
                    if (!actualHash.Equals(entry.Sha256, StringComparison.OrdinalIgnoreCase))
                    {
                        TryDeleteFile(tempPath);
                        throw new InvalidDataException(
                            $"Checksum mismatch for {entry.TargetPath}. Expected {entry.Sha256}, got {actualHash}.");
                    }
                }
            }

            try
            {
                File.Move(tempPath, destPath, overwrite: true);
            }
            catch (IOException ex)
            {
                TryDeleteFile(tempPath);
                throw new IOException(
                    $"Could not update {entry.TargetPath} because it is currently in use. Close Ashita / FINAL FANTASY XI / PlayOnline and try again. ({ex.Message})",
                    ex);
            }

            if (entry.Category.Equals("dat", StringComparison.OrdinalIgnoreCase) &&
                settings.SyncToCustomDatFolder &&
                !string.IsNullOrWhiteSpace(settings.CustomDatOverlayPath))
            {
                var customDest = Path.Combine(settings.CustomDatOverlayPath, entry.TargetPath.Replace('/', Path.DirectorySeparatorChar));
                Directory.CreateDirectory(Path.GetDirectoryName(customDest)!);
                File.Copy(destPath, customDest, overwrite: true);
            }

            completed++;
        }

        progress?.Report(new SyncProgress
        {
            Message = $"Synced {completed} SoulspireXI file(s).",
            Percent = 100
        });

        return completed;
    }

    public async Task EnsureAshitaAndToolsAsync(
        LauncherManifest manifest,
        LauncherSettings settings,
        IProgress<SyncProgress>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var ashitaDir = settings.AshitaPath;
        Directory.CreateDirectory(ashitaDir);

        if (!File.Exists(Path.Combine(ashitaDir, "Ashita-cli.exe")))
        {
            progress?.Report(new SyncProgress { Message = "Downloading Ashita v4...", Percent = 10 });
            await InstallAshitaAsync(manifest.Bootstrap.AshitaZipUrl, ashitaDir, cancellationToken).ConfigureAwait(false);
        }

        if (string.IsNullOrEmpty(FfxiInstallDetector.ResolveXiloaderPath(ashitaDir)))
        {
            progress?.Report(new SyncProgress { Message = "Downloading latest xiloader.exe...", Percent = 45 });
            await InstallLatestXiloaderAsync(manifest.Bootstrap.XiloaderLatestApiUrl, ashitaDir, cancellationToken).ConfigureAwait(false);
        }

        if (settings.EnablePivotOverlay && !File.Exists(Path.Combine(ashitaDir, "polplugins", "pivot.dll")))
        {
            progress?.Report(new SyncProgress { Message = "Downloading XIPivot plugin for Ashita v4...", Percent = 70 });
            await InstallLatestXipivotAsync(manifest.Bootstrap.XipivotLatestApiUrl, ashitaDir, cancellationToken).ConfigureAwait(false);
        }

        var metricsDir = Path.Combine(ashitaDir, "addons", "metrics");
        if (!File.Exists(Path.Combine(metricsDir, "metrics.lua")) ||
            !File.Exists(Path.Combine(metricsDir, "horizon.lua")) ||
            !File.Exists(Path.Combine(metricsDir, "initialization.lua")))
        {
            progress?.Report(new SyncProgress { Message = "Downloading Metrics parse addon for Ashita v4...", Percent = 80 });
            await InstallLatestGitHubAddonAsync(
                manifest.Bootstrap.MetricsLatestApiUrl,
                ashitaDir,
                addonFolderName: "metrics",
                entryFileName: "metrics.lua",
                displayName: "Metrics",
                cancellationToken).ConfigureAwait(false);
        }

        if (!File.Exists(Path.Combine(ashitaDir, "addons", "mobdb", "mobdb.lua")))
        {
            progress?.Report(new SyncProgress { Message = "Downloading MobDB mob level & info addon...", Percent = 88 });
            await InstallLatestGitHubAddonAsync(
                manifest.Bootstrap.MobDbLatestApiUrl,
                ashitaDir,
                addonFolderName: "mobdb",
                entryFileName: "mobdb.lua",
                displayName: "MobDB",
                cancellationToken).ConfigureAwait(false);
        }

        var kazenoeyeDir = Path.Combine(ashitaDir, "addons", "kazenoeye");
        if (!File.Exists(Path.Combine(kazenoeyeDir, "kazenoeye.lua")) ||
            !File.Exists(Path.Combine(kazenoeyeDir, "assets", "icons", "0.png")))
        {
            progress?.Report(new SyncProgress { Message = "Downloading Kazenoeye mob debuff HUD icons & base files...", Percent = 94 });
            await InstallLatestGitHubAddonAsync(
                manifest.Bootstrap.KazenoeyeLatestApiUrl,
                ashitaDir,
                addonFolderName: "kazenoeye",
                entryFileName: "kazenoeye.lua",
                displayName: "Kazenoeye",
                cancellationToken).ConfigureAwait(false);
        }

        progress?.Report(new SyncProgress { Message = "Ashita v4 prerequisites verified.", Percent = 100 });
    }

    private async Task InstallAshitaAsync(string zipUrl, string ashitaDir, CancellationToken cancellationToken)
    {
        var tempZip = Path.Combine(Path.GetTempPath(), $"overlords_ashita_{Guid.NewGuid():N}.zip");
        try
        {
            await DownloadFileAsync(zipUrl, tempZip, cancellationToken).ConfigureAwait(false);

            using var archive = ZipFile.OpenRead(tempZip);
            foreach (var entry in archive.Entries)
            {
                if (string.IsNullOrEmpty(entry.Name))
                {
                    continue;
                }

                // Strip leading repository folder name (e.g. Ashita-v4beta-main/)
                var parts = entry.FullName.Split(['/', '\\'], 2);
                var relPath = parts.Length == 2 ? parts[1] : parts[0];
                if (string.IsNullOrWhiteSpace(relPath))
                {
                    continue;
                }

                var dest = Path.GetFullPath(Path.Combine(ashitaDir, relPath.Replace('/', Path.DirectorySeparatorChar)));
                var rootFull = Path.GetFullPath(ashitaDir);
                if (!dest.StartsWith(rootFull, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
                entry.ExtractToFile(dest, overwrite: true);
            }
        }
        finally
        {
            TryDeleteFile(tempZip);
        }
    }

    private async Task InstallLatestXiloaderAsync(string latestApiUrl, string ashitaDir, CancellationToken cancellationToken)
    {
        var releaseJson = await _http.GetStringAsync(latestApiUrl, cancellationToken).ConfigureAwait(false);
        using var doc = JsonDocument.Parse(releaseJson);
        if (!doc.RootElement.TryGetProperty("assets", out var assets))
        {
            throw new InvalidOperationException("No release assets found for xiloader.");
        }

        string? exeUrl = null;
        string? zipUrl = null;

        foreach (var asset in assets.EnumerateArray())
        {
            var name = asset.GetProperty("name").GetString() ?? string.Empty;
            var url = asset.GetProperty("browser_download_url").GetString();
            if (string.IsNullOrWhiteSpace(url))
            {
                continue;
            }

            if (name.Equals("xiloader.exe", StringComparison.OrdinalIgnoreCase))
            {
                exeUrl = url;
                break;
            }

            if (name.Contains("xiloader", StringComparison.OrdinalIgnoreCase) &&
                name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
            {
                zipUrl = url;
            }
        }

        var bootloaderDir = Path.Combine(ashitaDir, "bootloader");
        Directory.CreateDirectory(bootloaderDir);
        var targetExe = Path.Combine(bootloaderDir, "xiloader.exe");

        if (exeUrl is not null)
        {
            await DownloadFileAsync(exeUrl, targetExe, cancellationToken).ConfigureAwait(false);
            return;
        }

        if (zipUrl is not null)
        {
            var tempZip = Path.Combine(Path.GetTempPath(), $"overlords_xiloader_{Guid.NewGuid():N}.zip");
            try
            {
                await DownloadFileAsync(zipUrl, tempZip, cancellationToken).ConfigureAwait(false);
                using var archive = ZipFile.OpenRead(tempZip);
                var exeEntry = archive.Entries.FirstOrDefault(e =>
                    e.Name.Equals("xiloader.exe", StringComparison.OrdinalIgnoreCase));
                if (exeEntry is null)
                {
                    throw new InvalidOperationException("xiloader.exe was not found inside release archive.");
                }

                exeEntry.ExtractToFile(targetExe, overwrite: true);
                return;
            }
            finally
            {
                TryDeleteFile(tempZip);
            }
        }

        throw new InvalidOperationException("Could not find xiloader.exe in latest LandSandBoat/xiloader release.");
    }

    private async Task InstallLatestXipivotAsync(string latestApiUrl, string ashitaDir, CancellationToken cancellationToken)
    {
        var releaseJson = await _http.GetStringAsync(latestApiUrl, cancellationToken).ConfigureAwait(false);
        using var doc = JsonDocument.Parse(releaseJson);
        if (!doc.RootElement.TryGetProperty("assets", out var assets))
        {
            throw new InvalidOperationException("No release assets found for XIPivot.");
        }

        string? ashita4ZipUrl = null;
        string? fallbackZipUrl = null;
        foreach (var asset in assets.EnumerateArray())
        {
            var name = asset.GetProperty("name").GetString() ?? string.Empty;
            var url = asset.GetProperty("browser_download_url").GetString();
            if (string.IsNullOrWhiteSpace(url) || !name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            fallbackZipUrl ??= url;

            if (name.Contains("Ashita_v4", StringComparison.OrdinalIgnoreCase) ||
                name.Contains("Ashita4", StringComparison.OrdinalIgnoreCase) ||
                name.Contains("v4", StringComparison.OrdinalIgnoreCase))
            {
                ashita4ZipUrl = url;
                break;
            }
        }

        var downloadUrl = ashita4ZipUrl ?? fallbackZipUrl;
        if (downloadUrl is null)
        {
            throw new InvalidOperationException("Could not find Ashita v4 archive in latest XIPivot release.");
        }

        var tempZip = Path.Combine(Path.GetTempPath(), $"overlords_xipivot_{Guid.NewGuid():N}.zip");
        try
        {
            await DownloadFileAsync(downloadUrl, tempZip, cancellationToken).ConfigureAwait(false);
            using var archive = ZipFile.OpenRead(tempZip);
            var polPluginsDir = Path.Combine(ashitaDir, "polplugins");
            Directory.CreateDirectory(polPluginsDir);

            var pivotEntries = archive.Entries
                .Where(e => !string.IsNullOrEmpty(e.Name) &&
                            e.Name.Equals("pivot.dll", StringComparison.OrdinalIgnoreCase))
                .ToList();

            var chosen = pivotEntries.FirstOrDefault(e =>
                             e.FullName.Contains("v4", StringComparison.OrdinalIgnoreCase) ||
                             e.FullName.Contains("polplugins", StringComparison.OrdinalIgnoreCase))
                         ?? pivotEntries.FirstOrDefault();

            if (chosen is null)
            {
                throw new InvalidOperationException("pivot.dll was not found inside XIPivot archive.");
            }

            chosen.ExtractToFile(Path.Combine(polPluginsDir, "pivot.dll"), overwrite: true);
        }
        finally
        {
            TryDeleteFile(tempZip);
        }
    }

    private async Task InstallLatestGitHubAddonAsync(
        string releaseApiUrl,
        string ashitaDir,
        string addonFolderName,
        string entryFileName,
        string displayName,
        CancellationToken cancellationToken)
    {
        var json = await _http.GetStringAsync(releaseApiUrl, cancellationToken).ConfigureAwait(false);
        using var doc = JsonDocument.Parse(json);

        string? addonZipUrl = null;
        if (doc.RootElement.TryGetProperty("assets", out var assetsProp) && assetsProp.ValueKind == JsonValueKind.Array)
        {
            string? fallbackZip = null;
            foreach (var asset in assetsProp.EnumerateArray())
            {
                var name = asset.GetProperty("name").GetString() ?? string.Empty;
                var url = asset.GetProperty("browser_download_url").GetString();
                if (!name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase) || string.IsNullOrWhiteSpace(url))
                {
                    continue;
                }

                fallbackZip ??= url;
                if (name.Contains(addonFolderName, StringComparison.OrdinalIgnoreCase))
                {
                    addonZipUrl = url;
                    break;
                }
            }

            addonZipUrl ??= fallbackZip;
        }

        if (string.IsNullOrWhiteSpace(addonZipUrl) &&
            doc.RootElement.TryGetProperty("zipball_url", out var zipballProp))
        {
            addonZipUrl = zipballProp.GetString();
        }

        if (string.IsNullOrWhiteSpace(addonZipUrl))
        {
            throw new InvalidOperationException($"Could not find {displayName} addon archive in latest GitHub release.");
        }

        var tempZip = Path.Combine(Path.GetTempPath(), $"overlords_{addonFolderName}_{Guid.NewGuid():N}.zip");
        try
        {
            await DownloadFileAsync(addonZipUrl, tempZip, cancellationToken).ConfigureAwait(false);
            var addonDir = Path.Combine(ashitaDir, "addons", addonFolderName);
            ExtractAddonZipToDirectory(tempZip, addonDir, entryFileName);
        }
        finally
        {
            TryDeleteFile(tempZip);
        }
    }

    public static void ExtractMetricsZipToDirectory(string zipPath, string metricsDir) =>
        ExtractAddonZipToDirectory(zipPath, metricsDir, "metrics.lua");

    public static void ExtractAddonZipToDirectory(string zipPath, string addonDir, string entryFileName)
    {
        Directory.CreateDirectory(addonDir);
        var rootFull = Path.GetFullPath(addonDir);
        var rootWithSep = rootFull.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;

        using var archive = ZipFile.OpenRead(zipPath);
        var entryPoint = archive.Entries.FirstOrDefault(e =>
            !string.IsNullOrEmpty(e.Name) &&
            e.Name.Equals(entryFileName, StringComparison.OrdinalIgnoreCase));

        var stripPrefix = string.Empty;
        if (entryPoint is not null)
        {
            var normalized = entryPoint.FullName.Replace('\\', '/').TrimStart('/');
            var slashIdx = normalized.LastIndexOf('/');
            if (slashIdx >= 0)
            {
                stripPrefix = normalized[..(slashIdx + 1)];
            }
        }

        foreach (var entry in archive.Entries)
        {
            if (string.IsNullOrEmpty(entry.Name))
            {
                continue;
            }

            var relPath = entry.FullName.Replace('\\', '/').TrimStart('/');
            if (!string.IsNullOrEmpty(stripPrefix))
            {
                if (!relPath.StartsWith(stripPrefix, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                relPath = relPath[stripPrefix.Length..];
            }

            if (string.IsNullOrWhiteSpace(relPath))
            {
                continue;
            }

            var dest = Path.GetFullPath(Path.Combine(rootFull, relPath.Replace('/', Path.DirectorySeparatorChar)));
            if (!dest.StartsWith(rootWithSep, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
            entry.ExtractToFile(dest, overwrite: true);
        }

        if (!File.Exists(Path.Combine(rootFull, entryFileName)))
        {
            throw new InvalidOperationException($"{entryFileName} was not found inside downloaded archive.");
        }
    }

    private async Task DownloadFileAsync(string url, string destinationPath, CancellationToken cancellationToken)
    {
        using var response = await _http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();

        await using var src = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
        await using var dst = new FileStream(destinationPath, FileMode.Create, FileAccess.Write, FileShare.None, 81920, useAsync: true);
        await src.CopyToAsync(dst, cancellationToken).ConfigureAwait(false);
    }

    public static bool FileMatchesHash(string filePath, string expectedSha256)
    {
        if (!File.Exists(filePath))
        {
            return false;
        }

        if (string.IsNullOrWhiteSpace(expectedSha256))
        {
            return true;
        }

        return ComputeSha256(filePath).Equals(expectedSha256, StringComparison.OrdinalIgnoreCase);
    }

    public static string ComputeSha256(string filePath)
    {
        using var stream = File.OpenRead(filePath);
        var hash = SHA256.HashData(stream);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    private static void TryDeleteFile(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
            // Ignore cleanup errors.
        }
    }
}
