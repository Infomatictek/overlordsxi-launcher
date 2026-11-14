using System.IO;
using OverlordsLauncher.Models;
using OverlordsLauncher.Services;
using Xunit;

namespace OverlordsLauncher.Tests;

public sealed class SettingsImportServiceTests
{
    [Fact]
    public void TryImportFromAshitaIni_ImportsDisplayInputLanguageAndGamepadSettings()
    {
        var tempFile = Path.Combine(Path.GetTempPath(), $"overlords_ini_test_{Guid.NewGuid():N}.ini");
        File.WriteAllText(tempFile, """
            [ashita.language]
            playonline = 3

            [ashita.input]
            gamepad.allowbackground = 1
            gamepad.disableenumeration = 1

            [ffxi.registry]
            0000 = 4
            0001 = 2560
            0002 = 1440
            0003 = 4096
            0004 = 4096
            0007 = 0
            0017 = 1
            0018 = 2
            0019 = 1
            0021 = 0
            0022 = 1
            0034 = 1
            0035 = 0
            0036 = 2
            0037 = 1920
            0038 = 1080
            padmode000 = 1,0,0,1,0,1
            padsin000 = 8,9,10,11,4,5,6,7
            padguid000 = -1
            padexsin000 = 1,2,3
            """);

        try
        {
            var settings = new LauncherSettings();
            var service = new SettingsImportService();

            var imported = service.TryImportFromAshitaIni(tempFile, settings, gamepadOnly: false);

            Assert.True(imported);
            Assert.Equal("EU", settings.Language);
            Assert.True(settings.GamepadAllowBackground);
            Assert.True(settings.GamepadDisableEnumeration);
            Assert.Equal(4, settings.MipMapping);
            Assert.Equal(2560, settings.WindowWidth);
            Assert.Equal(1440, settings.WindowHeight);
            Assert.Equal(WindowModeOption.Windowed, settings.WindowMode);
            Assert.False(settings.SoundEnabled);
            Assert.True(settings.BumpMapping);
            Assert.False(settings.HardwareMouse);
            Assert.True(settings.ShowOpeningMovie);
            Assert.True(settings.UseCustomGamepadConfig);
            Assert.True(settings.EnableGamepad);
            Assert.True(settings.EnableXInput);
            Assert.Equal("1,0,0,1,0,1", settings.PadMode);
            Assert.Equal("8,9,10,11,4,5,6,7", settings.PadSin);
            Assert.Equal(string.Empty, settings.PadGuid);
            Assert.Equal("1,2,3", settings.PadExSin);
        }
        finally
        {
            if (File.Exists(tempFile))
            {
                File.Delete(tempFile);
            }
        }
    }

    [Fact]
    public void TryImportFromAshitaIni_GamepadOnlyPreservesExistingResolution()
    {
        var tempFile = Path.Combine(Path.GetTempPath(), $"overlords_ini_padonly_{Guid.NewGuid():N}.ini");
        File.WriteAllText(tempFile, """
            [ffxi.registry]
            0001 = 1280
            0002 = 720
            padmode000 = 1,0,0,1,0,0
            padsin000 = 0,1,2,3
            """);

        try
        {
            var settings = new LauncherSettings
            {
                WindowWidth = 3840,
                WindowHeight = 2160
            };
            var service = new SettingsImportService();

            var imported = service.TryImportFromAshitaIni(tempFile, settings, gamepadOnly: true);

            Assert.True(imported);
            Assert.Equal(3840, settings.WindowWidth);
            Assert.Equal(2160, settings.WindowHeight);
            Assert.True(settings.EnableGamepad);
            Assert.False(settings.EnableXInput);
            Assert.Equal("0,1,2,3", settings.PadSin);
        }
        finally
        {
            if (File.Exists(tempFile))
            {
                File.Delete(tempFile);
            }
        }
    }
}
