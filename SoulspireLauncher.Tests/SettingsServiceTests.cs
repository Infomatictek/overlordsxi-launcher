using System.IO;
using System.Text;
using SoulspireLauncher.Models;
using SoulspireLauncher.Services;
using Xunit;

namespace SoulspireLauncher.Tests;

public sealed class SettingsServiceTests
{
    [Fact]
    public void EnsureAshitaDirectory_CreatesAshitaFolderInLauncherDirectoryAndDefaultsPath()
    {
        var tempRoot = Path.Combine(Path.GetTempPath(), $"overlords_settings_test_{Guid.NewGuid():N}");
        var launcherDir = Path.Combine(tempRoot, "Launcher");
        var appDataDir = Path.Combine(tempRoot, "AppData");
        Directory.CreateDirectory(launcherDir);

        try
        {
            var service = new SettingsService(launcherDir, appDataDir);
            var settings = service.Load();
            service.EnsureAshitaDirectory(settings);

            var expectedAshitaDir = Path.Combine(launcherDir, "Ashita");
            Assert.Equal(expectedAshitaDir, settings.AshitaPath);
            Assert.False(settings.UseCustomAshitaPath);
            Assert.True(Directory.Exists(expectedAshitaDir));
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
    public void Load_TracksCurrentLauncherDirectoryUnlessCustomAshitaPathIsSet()
    {
        var tempRoot = Path.Combine(Path.GetTempPath(), $"overlords_settings_move_test_{Guid.NewGuid():N}");
        var oldLauncherDir = Path.Combine(tempRoot, "Downloads");
        var newLauncherDir = Path.Combine(tempRoot, "Games", "SoulspireXI");
        var customAshitaDir = Path.Combine(tempRoot, "MyCustomAshita");
        var appDataDir = Path.Combine(tempRoot, "AppData");
        Directory.CreateDirectory(oldLauncherDir);
        Directory.CreateDirectory(newLauncherDir);
        Directory.CreateDirectory(customAshitaDir);

        try
        {
            // Default settings follow launcher when moved to a new directory.
            var firstService = new SettingsService(oldLauncherDir, appDataDir);
            var initial = firstService.Load();
            firstService.Save(initial, plainPassword: null);

            var movedService = new SettingsService(newLauncherDir, appDataDir);
            var moved = movedService.Load();
            movedService.EnsureAshitaDirectory(moved);

            Assert.Equal(Path.Combine(newLauncherDir, "Ashita"), moved.AshitaPath);
            Assert.True(Directory.Exists(Path.Combine(newLauncherDir, "Ashita")));

            // Explicit custom path is preserved even if launcher moves.
            moved.AshitaPath = customAshitaDir;
            moved.UseCustomAshitaPath = true;
            movedService.Save(moved, plainPassword: null);

            var afterCustom = movedService.Load();
            Assert.True(afterCustom.UseCustomAshitaPath);
            Assert.Equal(customAshitaDir, afterCustom.AshitaPath);
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
    public void Load_MigratesLegacyDefaultAshitaPathAndPreservesExistingCustomInstall()
    {
        var tempRoot = Path.Combine(Path.GetTempPath(), $"overlords_settings_legacy_test_{Guid.NewGuid():N}");
        var launcherDir = Path.Combine(tempRoot, "Launcher");
        var appDataDir = Path.Combine(tempRoot, "AppData");
        var legacyDefaultDir = Path.Combine(tempRoot, "OldFolder", "Ashita");
        var legacyCustomDir = Path.Combine(tempRoot, "CustomAshitaFolder");
        Directory.CreateDirectory(launcherDir);
        Directory.CreateDirectory(appDataDir);
        Directory.CreateDirectory(legacyDefaultDir);
        Directory.CreateDirectory(legacyCustomDir);

        try
        {
            var settingsPath = Path.Combine(appDataDir, "settings.json");

            // Legacy default (.../Ashita) without UseCustomAshitaPath moves to current launcher/Ashita.
            File.WriteAllText(
                settingsPath,
                $$"""{"AshitaPath":"{{legacyDefaultDir.Replace("\\", "\\\\")}}"}""",
                Encoding.UTF8);

            var service = new SettingsService(launcherDir, appDataDir);
            var migrated = service.Load();
            Assert.False(migrated.UseCustomAshitaPath);
            Assert.Equal(Path.Combine(launcherDir, "Ashita"), migrated.AshitaPath);

            // Legacy custom install with Ashita-cli.exe in a non-"Ashita" folder is preserved.
            File.WriteAllText(Path.Combine(legacyCustomDir, "Ashita-cli.exe"), "stub", Encoding.UTF8);
            File.WriteAllText(
                settingsPath,
                $$"""{"AshitaPath":"{{legacyCustomDir.Replace("\\", "\\\\")}}"}""",
                Encoding.UTF8);

            var preserved = service.Load();
            Assert.True(preserved.UseCustomAshitaPath);
            Assert.Equal(legacyCustomDir, preserved.AshitaPath);
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
