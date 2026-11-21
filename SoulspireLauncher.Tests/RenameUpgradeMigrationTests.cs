using System.IO;
using System.Text;
using System.Text.Json;
using SoulspireLauncher.Models;
using SoulspireLauncher.Services;
using Xunit;

namespace SoulspireLauncher.Tests;

public sealed class RenameUpgradeMigrationTests
{
    [Fact]
    public void CleanInstall_WritesSoulspireConfigsAndLoadsEachAddonOnce()
    {
        var root = Path.Combine(Path.GetTempPath(), $"soulspire_clean_{Guid.NewGuid():N}");
        var ashitaDir = Path.Combine(root, "Ashita");
        Directory.CreateDirectory(ashitaDir);

        try
        {
            var settings = LauncherSettings.CreateDefault(root);
            var gen = new AshitaConfigGenerator();
            gen.WriteAllConfigs(ashitaDir, settings, "play.soulspirexi.com", false, null, "xiloader.exe");

            var bootIni = File.ReadAllText(Path.Combine(ashitaDir, "config", "boot", "soulspirexi.ini"), Encoding.UTF8);
            var pivotIni = File.ReadAllText(Path.Combine(ashitaDir, "config", "pivot", "soulspirexi.ini"), Encoding.UTF8);
            var script = File.ReadAllText(Path.Combine(ashitaDir, "scripts", "soulspirexi.txt"), Encoding.UTF8);

            Assert.Contains("name = SoulspireXI", bootIni);
            Assert.Contains("script = soulspirexi.txt", bootIni);
            Assert.Contains("pivot = soulspirexi", bootIni);
            Assert.Contains("0=soulspirexi", pivotIni);

            var lines = script.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries)
                              .Select(l => l.Trim())
                              .ToList();

            foreach (var addon in new[] { "soulspire_talents", "soulspire_gear", "soulspire_soulhud", "soulspire_soul_actions" })
            {
                Assert.Equal(1, lines.Count(l => l.Equals($"/addon load {addon}", StringComparison.OrdinalIgnoreCase)));
            }

            Assert.DoesNotContain(lines, l => l.Contains("overlords_", StringComparison.OrdinalIgnoreCase));
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void UpgradeFromLegacyOverlordsFixture_PreservesConfigRemovesRetiredAddonsAndIsIdempotent()
    {
        var root = Path.Combine(Path.GetTempPath(), $"soulspire_upgrade_{Guid.NewGuid():N}");
        var launcherDir = Path.Combine(root, "Launcher");
        var ashitaDir = Path.Combine(launcherDir, "Ashita");
        var legacyAppData = Path.Combine(root, "AppData", "OverlordsXI");
        var newAppData = Path.Combine(root, "AppData", "SoulspireXI");

        Directory.CreateDirectory(launcherDir);
        Directory.CreateDirectory(Path.Combine(ashitaDir, "scripts"));
        Directory.CreateDirectory(legacyAppData);

        try
        {
            // 1. Seed legacy OverlordsXI AppData settings + legacy overlords-server.json
            var legacySettings = new LauncherSettings
            {
                Username = "legacyhero",
                WindowWidth = 2560,
                WindowHeight = 1440,
                AutoLoadTalentsAddon = true,
                AutoLoadGearAddon = true,
                AutoLoadSoulHudAddon = true
            };
            File.WriteAllText(
                Path.Combine(legacyAppData, "settings.json"),
                JsonSerializer.Serialize(legacySettings),
                Encoding.UTF8);
            File.WriteAllText(
                Path.Combine(launcherDir, "overlords-server.json"),
                """{"DefaultHost":"play.soulspirexi.com","ServerName":"SoulspireXI"}""",
                Encoding.UTF8);

            // 2. Seed legacy overlordsxi.txt with old addon loads + custom player addon
            File.WriteAllText(
                Path.Combine(ashitaDir, "scripts", "overlordsxi.txt"),
                string.Join("\n",
                    "# OverlordsXI Ashita v4 startup script",
                    "/load addons",
                    "/wait 3",
                    "/addon load fps",
                    "/addon load timestamp",
                    "/addon load my_custom_addon",
                    "/addon load overlords_talents",
                    "/addon load overlords_gear",
                    "/addon load overlords_soulhud",
                    "/addon load overlords_soul_actions",
                    "/addon load overlords_boost"),
                Encoding.UTF8);

            // 3. Seed legacy addon folders & metrics/overlords.lua
            foreach (var oldFolder in ManifestUpdateService.RetiredAddonFolders)
            {
                var dir = Path.Combine(ashitaDir, "addons", oldFolder);
                Directory.CreateDirectory(dir);
                File.WriteAllText(Path.Combine(dir, $"{oldFolder}.lua"), "-- legacy", Encoding.UTF8);
            }
            var metricsDir = Path.Combine(ashitaDir, "addons", "metrics");
            Directory.CreateDirectory(metricsDir);
            File.WriteAllText(Path.Combine(metricsDir, "overlords.lua"), "-- legacy metrics", Encoding.UTF8);

            // Run normal launcher upgrade entry points TWICE to prove idempotency
            var settingsSvc = new SettingsService(launcherDir, newAppData, legacyAppData);
            var gen = new AshitaConfigGenerator();

            string? firstRunScript = null;
            for (var run = 1; run <= 2; run++)
            {
                var loaded = settingsSvc.Load();
                Assert.Equal("legacyhero", loaded.Username);
                Assert.Equal(2560, loaded.WindowWidth);
                Assert.Equal(1440, loaded.WindowHeight);
                Assert.True(File.Exists(Path.Combine(newAppData, "settings.json")));

                var localOverride = settingsSvc.LoadLocalServerOverride();
                Assert.NotNull(localOverride);
                Assert.Equal("play.soulspirexi.com", localOverride!.DefaultHost);

                ManifestUpdateService.RemoveRetiredAddons(loaded);
                gen.WriteAllConfigs(ashitaDir, loaded, "play.soulspirexi.com", false, null, "xiloader.exe");

                var script = File.ReadAllText(Path.Combine(ashitaDir, "scripts", "soulspirexi.txt"), Encoding.UTF8);
                if (run == 1)
                {
                    firstRunScript = script;
                }
                else
                {
                    Assert.Equal(firstRunScript, script);
                }

                var lines = script.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries)
                                  .Select(l => l.Trim())
                                  .ToList();

                // Player's custom line preserved
                Assert.Equal(1, lines.Count(l => l.Equals("/addon load my_custom_addon", StringComparison.OrdinalIgnoreCase)));

                // Every SoulspireXI addon loaded exactly once; zero legacy overlords_* loads remain
                foreach (var addon in new[] { "soulspire_talents", "soulspire_gear", "soulspire_soulhud", "soulspire_soul_actions" })
                {
                    Assert.Equal(1, lines.Count(l => l.Equals($"/addon load {addon}", StringComparison.OrdinalIgnoreCase)));
                }
                Assert.DoesNotContain(lines, l => l.Contains("overlords_", StringComparison.OrdinalIgnoreCase));

                // All retired folders & legacy metrics hook removed
                foreach (var oldFolder in ManifestUpdateService.RetiredAddonFolders)
                {
                    Assert.False(Directory.Exists(Path.Combine(ashitaDir, "addons", oldFolder)));
                }
                Assert.False(File.Exists(Path.Combine(metricsDir, "overlords.lua")));
            }
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void SelfUpdateParser_PrefersSoulspireExeAndFallsBackToLegacyOverlordsExe()
    {
        const string bothAssetsJson = """
        {
          "tag_name": "v2.0.0",
          "draft": false,
          "prerelease": false,
          "html_url": "https://github.com/Infomatictek/soulspirexi-launcher/releases/tag/v2.0.0",
          "assets": [
            { "name": "OverlordsLauncher.exe", "browser_download_url": "https://example.test/OverlordsLauncher.exe", "size": 1000000 },
            { "name": "SoulspireLauncher.exe", "browser_download_url": "https://example.test/SoulspireLauncher.exe", "size": 1000000 }
          ]
        }
        """;

        var both = LauncherSelfUpdateService.ParseLatestReleaseJson(bothAssetsJson, new Version(1, 0, 0));
        Assert.True(both.UpdateAvailable);
        Assert.EndsWith("SoulspireLauncher.exe", both.DownloadUrl);

        const string legacyOnlyJson = """
        {
          "tag_name": "v2.0.0",
          "draft": false,
          "prerelease": false,
          "html_url": "https://github.com/Infomatictek/soulspirexi-launcher/releases/tag/v2.0.0",
          "assets": [
            { "name": "OverlordsLauncher.exe", "browser_download_url": "https://example.test/OverlordsLauncher.exe", "size": 1000000 }
          ]
        }
        """;

        var legacy = LauncherSelfUpdateService.ParseLatestReleaseJson(legacyOnlyJson, new Version(1, 0, 0));
        Assert.True(legacy.UpdateAvailable);
        Assert.EndsWith("OverlordsLauncher.exe", legacy.DownloadUrl);
    }
}
