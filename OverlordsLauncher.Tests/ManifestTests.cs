using System.IO;
using System.IO.Compression;
using System.Text;
using OverlordsLauncher.Models;
using OverlordsLauncher.Services;
using Xunit;

namespace OverlordsLauncher.Tests;

public sealed class ManifestTests
{
    [Fact]
    public void LoadEmbeddedManifest_ContainsExpectedFilesAndDefaults()
    {
        var service = new ManifestUpdateService();
        var manifest = service.LoadEmbeddedManifest();

        Assert.Equal("OverlordsXI", manifest.ServerName);
        Assert.Equal("Infomatictek", manifest.Repo.Owner);
        Assert.Equal("overlordsxi-launcher", manifest.Repo.Name);
        Assert.True(manifest.Files.Count >= 5);
        Assert.Contains(manifest.Files, f =>
            f.Category == "addon" &&
            f.TargetPath == "overlords_talents/overlords_talents.lua" &&
            !string.IsNullOrWhiteSpace(f.Sha256));
        Assert.Contains(manifest.Files, f =>
            f.Category == "addon" &&
            f.TargetPath == "crystalsocket/crystalsocket.lua" &&
            !string.IsNullOrWhiteSpace(f.Sha256));
        Assert.Contains(manifest.Files, f =>
            f.Category == "addon" &&
            f.TargetPath == "crystalsocket/assets/sensei.png" &&
            !string.IsNullOrWhiteSpace(f.Sha256));
        Assert.Contains(manifest.Files, f =>
            f.Category == "dat" &&
            f.TargetPath == "ROM/118/108.DAT" &&
            !string.IsNullOrWhiteSpace(f.Sha256));
    }

    [Fact]
    public void ApplyLocalOverride_UpdatesProvidedFieldsAndPreservesOthers()
    {
        var manifest = new LauncherManifest
        {
            ServerName = "OverlordsXI",
            DefaultHost = "127.0.0.1",
            UseHairpin = false,
            Ports = new ManifestPorts { Lobby = 54231, Auth = 54001, Search = 54002 }
        };

        var localOverride = new LocalServerOverride
        {
            ServerName = " OverlordsXI Live ",
            DefaultHost = " play.overlordsxi.net ",
            UseHairpin = true,
            LobbyPort = 54235
        };

        ManifestUpdateService.ApplyLocalOverride(manifest, localOverride);

        Assert.Equal("OverlordsXI Live", manifest.ServerName);
        Assert.Equal("play.overlordsxi.net", manifest.DefaultHost);
        Assert.True(manifest.UseHairpin);
        Assert.Equal(54235, manifest.Ports.Lobby);
        Assert.Equal(54001, manifest.Ports.Auth);
        Assert.Equal(54002, manifest.Ports.Search);
    }

    [Fact]
    public void ResolveTargetFilePath_RoutesDatAndAddonCategoriesCorrectly()
    {
        var settings = new LauncherSettings
        {
            AshitaPath = Path.Combine("C:", "Games", "Ashita")
        };

        var datEntry = new ManifestFileEntry
        {
            Category = "dat",
            TargetPath = "ROM/118/108.DAT"
        };
        var addonEntry = new ManifestFileEntry
        {
            Category = "addon",
            TargetPath = "overlords_talents/overlords_talents.lua"
        };

        var datDest = ManifestUpdateService.ResolveTargetFilePath(settings, datEntry);
        var addonDest = ManifestUpdateService.ResolveTargetFilePath(settings, addonEntry);

        Assert.Equal(
            Path.Combine("C:", "Games", "Ashita", "polplugins", "DATs", "overlordsxi", "ROM", "118", "108.DAT"),
            datDest);
        Assert.Equal(
            Path.Combine("C:", "Games", "Ashita", "addons", "overlords_talents", "overlords_talents.lua"),
            addonDest);
    }

    [Fact]
    public void FileMatchesHash_And_GetOutdatedFiles_DetectMissingAndModifiedFiles()
    {
        var tempRoot = Path.Combine(Path.GetTempPath(), $"overlords_launcher_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            var settings = new LauncherSettings
            {
                AshitaPath = tempRoot
            };

            var sampleFile = Path.Combine(tempRoot, "addons", "overlords_talents", "overlords_talents.lua");
            Directory.CreateDirectory(Path.GetDirectoryName(sampleFile)!);
            File.WriteAllText(sampleFile, "-- overlords test", Encoding.UTF8);

            var expectedHash = ManifestUpdateService.ComputeSha256(sampleFile);
            Assert.True(ManifestUpdateService.FileMatchesHash(sampleFile, expectedHash));
            Assert.False(ManifestUpdateService.FileMatchesHash(sampleFile, "0000000000000000"));

            var manifest = new LauncherManifest
            {
                Files =
                [
                    new ManifestFileEntry
                    {
                        Category = "addon",
                        TargetPath = "overlords_talents/overlords_talents.lua",
                        Sha256 = expectedHash
                    },
                    new ManifestFileEntry
                    {
                        Category = "dat",
                        TargetPath = "ROM/118/108.DAT",
                        Sha256 = "deadbeef"
                    }
                ]
            };

            var service = new ManifestUpdateService();
            var outdated = service.GetOutdatedFiles(manifest, settings, forceAll: false);
            Assert.Single(outdated);
            Assert.Equal("ROM/118/108.DAT", outdated[0].TargetPath);

            var forced = service.GetOutdatedFiles(manifest, settings, forceAll: true);
            Assert.Equal(2, forced.Count);
        }
        finally
        {
            if (Directory.Exists(tempRoot))
            {
                Directory.Delete(tempRoot, recursive: true);
            }
        }
    }

    [Fact]
    public void ExtractMetricsZipToDirectory_HandlesFlatAndNestedArchives()
    {
        var tempRoot = Path.Combine(Path.GetTempPath(), $"overlords_metrics_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            var zipPath = Path.Combine(tempRoot, "metrics.zip");
            using (var archive = ZipFile.Open(zipPath, ZipArchiveMode.Create))
            {
                var mainEntry = archive.CreateEntry("metrics/metrics.lua");
                using (var writer = new StreamWriter(mainEntry.Open()))
                {
                    writer.Write("-- metrics entry");
                }

                var subEntry = archive.CreateEntry("metrics/modules/parse/_parse.lua");
                using (var writer = new StreamWriter(subEntry.Open()))
                {
                    writer.Write("-- parse module");
                }
            }

            var targetDir = Path.Combine(tempRoot, "addons", "metrics");
            ManifestUpdateService.ExtractMetricsZipToDirectory(zipPath, targetDir);

            Assert.True(File.Exists(Path.Combine(targetDir, "metrics.lua")));
            Assert.True(File.Exists(Path.Combine(targetDir, "modules", "parse", "_parse.lua")));

            var embedded = new ManifestUpdateService().LoadEmbeddedManifest();
            Assert.Contains("RaraProjects/metrics", embedded.Bootstrap.MetricsLatestApiUrl);
            Assert.Contains("ThornyFFXI/mobdb", embedded.Bootstrap.MobDbLatestApiUrl);
            Assert.Contains("kazenohito/kazenoeye", embedded.Bootstrap.KazenoeyeLatestApiUrl);
        }
        finally
        {
            if (Directory.Exists(tempRoot))
            {
                Directory.Delete(tempRoot, recursive: true);
            }
        }
    }

    [Fact]
    public void ExtractAddonZipToDirectory_HandlesMobDbAndKazenoeyeArchiveLayouts()
    {
        var tempRoot = Path.Combine(Path.GetTempPath(), $"overlords_qol_addons_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            // Layout 1: mobdb release zip (addons/mobdb/...)
            var mobdbZip = Path.Combine(tempRoot, "mobdb.zip");
            using (var archive = ZipFile.Open(mobdbZip, ZipArchiveMode.Create))
            {
                using (var writer = new StreamWriter(archive.CreateEntry("addons/mobdb/mobdb.lua").Open()))
                {
                    writer.Write("-- mobdb entry");
                }

                using (var writer = new StreamWriter(archive.CreateEntry("addons/mobdb/data/1.lua").Open()))
                {
                    writer.Write("-- zone 1");
                }
            }

            var mobdbDir = Path.Combine(tempRoot, "addons", "mobdb");
            ManifestUpdateService.ExtractAddonZipToDirectory(mobdbZip, mobdbDir, "mobdb.lua");
            Assert.True(File.Exists(Path.Combine(mobdbDir, "mobdb.lua")));
            Assert.True(File.Exists(Path.Combine(mobdbDir, "data", "1.lua")));

            // Layout 2: GitHub zipball archive (kazenohito-kazenoeye-sha/...)
            var kazenoeyeZip = Path.Combine(tempRoot, "kazenoeye.zip");
            using (var archive = ZipFile.Open(kazenoeyeZip, ZipArchiveMode.Create))
            {
                using (var writer = new StreamWriter(archive.CreateEntry("kazenohito-kazenoeye-abc123/kazenoeye.lua").Open()))
                {
                    writer.Write("-- kazenoeye entry");
                }

                using (var writer = new StreamWriter(archive.CreateEntry("kazenohito-kazenoeye-abc123/util/debuffhandler.lua").Open()))
                {
                    writer.Write("-- debuff handler");
                }
            }

            var kazenoeyeDir = Path.Combine(tempRoot, "addons", "kazenoeye");
            ManifestUpdateService.ExtractAddonZipToDirectory(kazenoeyeZip, kazenoeyeDir, "kazenoeye.lua");
            Assert.True(File.Exists(Path.Combine(kazenoeyeDir, "kazenoeye.lua")));
            Assert.True(File.Exists(Path.Combine(kazenoeyeDir, "util", "debuffhandler.lua")));
        }
        finally
        {
            if (Directory.Exists(tempRoot))
            {
                Directory.Delete(tempRoot, recursive: true);
            }
        }
    }
}
