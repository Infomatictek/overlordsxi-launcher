using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Text.Json;
using SoulspireLauncher.Models;

namespace SoulspireLauncher.Services;

public sealed class LauncherUpdateCheckResult
{
    public bool UpdateAvailable { get; init; }
    public Version CurrentVersion { get; init; } = new(1, 0, 0);
    public Version? LatestVersion { get; init; }
    public string LatestTag { get; init; } = string.Empty;
    public string DownloadUrl { get; init; } = string.Empty;
    public long ExpectedSize { get; init; }
    public string ReleaseUrl { get; init; } = string.Empty;
}

public sealed class LauncherSelfUpdateService
{
    public const string JustUpdatedArg = "--just-updated";
    private const string LauncherExeAssetName = "SoulspireLauncher.exe";
    private const string LegacyLauncherExeAssetName = "OverlordsLauncher.exe";
    private const long MinimumValidExeBytes = 512 * 1024;

    private readonly HttpClient _http;

    public LauncherSelfUpdateService(HttpClient? httpClient = null)
    {
        _http = httpClient ?? ManifestUpdateService.CreateDefaultHttpClient();
    }

    public static Version GetCurrentVersion()
    {
        var raw = Assembly.GetExecutingAssembly().GetName().Version ?? new Version(1, 0, 0);
        return NormalizeVersion(raw);
    }

    public static Version NormalizeVersion(Version version)
    {
        return new Version(
            Math.Max(0, version.Major),
            Math.Max(0, version.Minor),
            Math.Max(0, version.Build));
    }

    public static bool TryParseVersionTag(string? tagOrVersion, out Version parsedVersion)
    {
        parsedVersion = new Version(0, 0, 0);
        if (string.IsNullOrWhiteSpace(tagOrVersion))
        {
            return false;
        }

        var trimmed = tagOrVersion.Trim().TrimStart('v', 'V');
        var separatorIndex = trimmed.IndexOfAny(['-', '+']);
        if (separatorIndex > 0)
        {
            trimmed = trimmed[..separatorIndex];
        }

        if (!Version.TryParse(trimmed, out var raw))
        {
            return false;
        }

        parsedVersion = NormalizeVersion(raw);
        return true;
    }

    public static bool IsNewerVersion(Version currentVersion, string? latestTag, out Version? parsedLatest)
    {
        parsedLatest = null;
        if (!TryParseVersionTag(latestTag, out var latest))
        {
            return false;
        }

        parsedLatest = latest;
        return latest > NormalizeVersion(currentVersion);
    }

    public static LauncherUpdateCheckResult ParseLatestReleaseJson(string json, Version currentVersion)
    {
        var normalizedCurrent = NormalizeVersion(currentVersion);
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        var isDraft = root.TryGetProperty("draft", out var draftProp) && draftProp.ValueKind == JsonValueKind.True;
        var isPrerelease = root.TryGetProperty("prerelease", out var preProp) && preProp.ValueKind == JsonValueKind.True;
        var tagName = root.TryGetProperty("tag_name", out var tagProp) ? tagProp.GetString() ?? string.Empty : string.Empty;
        var htmlUrl = root.TryGetProperty("html_url", out var htmlProp) ? htmlProp.GetString() ?? string.Empty : string.Empty;

        string downloadUrl = string.Empty;
        long expectedSize = 0;

        if (root.TryGetProperty("assets", out var assetsProp) && assetsProp.ValueKind == JsonValueKind.Array)
        {
            foreach (var preferredName in new[] { LauncherExeAssetName, LegacyLauncherExeAssetName })
            {
                foreach (var asset in assetsProp.EnumerateArray())
                {
                    var name = asset.TryGetProperty("name", out var nameProp) ? nameProp.GetString() : null;
                    if (!string.Equals(name, preferredName, StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }

                    downloadUrl = asset.TryGetProperty("browser_download_url", out var urlProp) ? urlProp.GetString() ?? string.Empty : string.Empty;
                    if (asset.TryGetProperty("size", out var sizeProp) && sizeProp.TryGetInt64(out var size))
                    {
                        expectedSize = size;
                    }

                    break;
                }

                if (!string.IsNullOrWhiteSpace(downloadUrl))
                {
                    break;
                }
            }
        }

        Version? latestVersion = null;
        var isNewer = !isDraft &&
                      !isPrerelease &&
                      IsNewerVersion(normalizedCurrent, tagName, out latestVersion) &&
                      !string.IsNullOrWhiteSpace(downloadUrl);

        return new LauncherUpdateCheckResult
        {
            UpdateAvailable = isNewer,
            CurrentVersion = normalizedCurrent,
            LatestVersion = latestVersion,
            LatestTag = tagName,
            DownloadUrl = downloadUrl,
            ExpectedSize = expectedSize,
            ReleaseUrl = htmlUrl
        };
    }

    public async Task<LauncherUpdateCheckResult> CheckForUpdateAsync(
        LauncherManifest manifest,
        CancellationToken cancellationToken = default)
    {
        var currentVersion = GetCurrentVersion();
        var owner = string.IsNullOrWhiteSpace(manifest.Repo.Owner) ? "Infomatictek" : manifest.Repo.Owner.Trim();
        var repo = string.IsNullOrWhiteSpace(manifest.Repo.Name) ? "soulspirexi-launcher" : manifest.Repo.Name.Trim();
        var apiUrl = $"https://api.github.com/repos/{owner}/{repo}/releases/latest";

        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(TimeSpan.FromSeconds(10));

        var json = await _http.GetStringAsync(apiUrl, cts.Token).ConfigureAwait(false);
        return ParseLatestReleaseJson(json, currentVersion);
    }

    public static string? GetCurrentExecutablePath()
    {
        var path = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(path))
        {
            try
            {
                path = Process.GetCurrentProcess().MainModule?.FileName;
            }
            catch
            {
                path = null;
            }
        }

        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            return null;
        }

        var fileName = Path.GetFileName(path);
        if (!fileName.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ||
            fileName.Equals("dotnet.exe", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        return path;
    }

    public static bool CanSelfUpdateInPlace(out string? exePath, out string reason)
    {
        exePath = GetCurrentExecutablePath();
        if (string.IsNullOrWhiteSpace(exePath))
        {
            reason = "Self-update is only available when running the packaged SoulspireLauncher.exe.";
            return false;
        }

        var dir = Path.GetDirectoryName(exePath);
        if (string.IsNullOrWhiteSpace(dir))
        {
            reason = "Cannot determine launcher directory.";
            return false;
        }

        try
        {
            var probe = Path.Combine(dir, $".update-write-test-{Environment.ProcessId}.tmp");
            File.WriteAllText(probe, "ok");
            File.Delete(probe);
            reason = string.Empty;
            return true;
        }
        catch (Exception ex)
        {
            reason = $"Launcher folder is not writable ({ex.Message}). Move SoulspireLauncher.exe to a user folder or update manually.";
            return false;
        }
    }

    public async Task<string> DownloadUpdateAsync(
        LauncherUpdateCheckResult update,
        IProgress<SyncProgress>? progress = null,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(update.DownloadUrl))
        {
            throw new InvalidOperationException("No download URL provided for launcher update.");
        }

        var stagingDir = GetStagingDirectory();
        Directory.CreateDirectory(stagingDir);

        var safeTag = string.IsNullOrWhiteSpace(update.LatestTag) ? "latest" : update.LatestTag.Trim();
        var stagedPath = Path.Combine(stagingDir, $"SoulspireLauncher-{safeTag}.exe");
        if (File.Exists(stagedPath))
        {
            File.Delete(stagedPath);
        }

        progress?.Report(new SyncProgress
        {
            Message = $"Downloading launcher {safeTag}...",
            Percent = 10
        });

        using var response = await _http.GetAsync(update.DownloadUrl, HttpCompletionOption.ResponseHeadersRead, cancellationToken)
            .ConfigureAwait(false);
        response.EnsureSuccessStatusCode();

        var totalBytes = response.Content.Headers.ContentLength ?? update.ExpectedSize;
        await using (var remoteStream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false))
        await using (var fileStream = File.Create(stagedPath))
        {
            var buffer = new byte[81920];
            long totalRead = 0;
            int read;
            while ((read = await remoteStream.ReadAsync(buffer, cancellationToken).ConfigureAwait(false)) > 0)
            {
                await fileStream.WriteAsync(buffer.AsMemory(0, read), cancellationToken).ConfigureAwait(false);
                totalRead += read;

                if (totalBytes > 0)
                {
                    var pct = 10 + (85.0 * totalRead / totalBytes);
                    progress?.Report(new SyncProgress
                    {
                        Message = $"Downloading launcher {safeTag}... ({totalRead / (1024 * 1024.0):F1} MB)",
                        Percent = Math.Min(95, pct)
                    });
                }
            }
        }

        var info = new FileInfo(stagedPath);
        if (info.Length < MinimumValidExeBytes || (update.ExpectedSize > 0 && info.Length != update.ExpectedSize))
        {
            try
            {
                File.Delete(stagedPath);
            }
            catch
            {
                // Ignore cleanup failure.
            }

            throw new InvalidDataException($"Downloaded launcher binary size ({info.Length} bytes) did not match expected release size.");
        }

        progress?.Report(new SyncProgress
        {
            Message = $"Downloaded launcher {safeTag}. Restarting...",
            Percent = 100
        });

        return stagedPath;
    }

    public void LaunchUpdaterAndPrepareRestart(string stagedExePath, string targetExePath)
    {
        var stagingDir = GetStagingDirectory();
        Directory.CreateDirectory(stagingDir);

        var scriptPath = Path.Combine(stagingDir, "apply-soulspire-update.cmd");
        var scriptContent = BuildUpdaterBatchScript(Environment.ProcessId, stagedExePath, targetExePath);
        File.WriteAllText(scriptPath, scriptContent);

        Process.Start(new ProcessStartInfo
        {
            FileName = "cmd.exe",
            Arguments = $"/c \"{scriptPath}\"",
            WorkingDirectory = stagingDir,
            CreateNoWindow = true,
            UseShellExecute = false,
            WindowStyle = ProcessWindowStyle.Hidden
        });
    }

    public static string BuildUpdaterBatchScript(int currentPid, string stagedExePath, string targetExePath)
    {
        return string.Join(
            "\r\n",
            "@echo off",
            "setlocal",
            $"set \"TARGET_PID={currentPid}\"",
            $"set \"SRC={stagedExePath}\"",
            $"set \"DST={targetExePath}\"",
            "set /a WAIT_COUNT=0",
            ":waitloop",
            "tasklist /FI \"PID eq %TARGET_PID%\" /FO CSV /NH 2>nul | findstr /C:\",\\\"%TARGET_PID%\\\",\" >nul",
            "if not errorlevel 1 (",
            "  set /a WAIT_COUNT+=1",
            "  if %WAIT_COUNT% GEQ 30 goto copystep",
            "  ping -n 2 127.0.0.1 >nul",
            "  goto waitloop",
            ")",
            ":copystep",
            "set /a COPY_COUNT=0",
            ":copyloop",
            "copy /Y \"%SRC%\" \"%DST%\" >nul 2>&1",
            "if errorlevel 1 (",
            "  set /a COPY_COUNT+=1",
            "  if %COPY_COUNT% GEQ 20 goto cleanup",
            "  ping -n 2 127.0.0.1 >nul",
            "  goto copyloop",
            ")",
            "del /F /Q \"%SRC%\" >nul 2>&1",
            $"start \"\" \"%DST%\" {JustUpdatedArg}",
            ":cleanup",
            "del /F /Q \"%~f0\" >nul 2>&1");
    }

    public static void CleanupStagingDirectory()
    {
        try
        {
            var dir = GetStagingDirectory();
            if (Directory.Exists(dir))
            {
                Directory.Delete(dir, recursive: true);
            }
        }
        catch
        {
            // Best-effort cleanup of temp update files.
        }
    }

    private static string GetStagingDirectory() =>
        Path.Combine(Path.GetTempPath(), "SoulspireLauncher-Update");
}
