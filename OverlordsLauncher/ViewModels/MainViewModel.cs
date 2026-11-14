using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using Microsoft.Win32;
using OverlordsLauncher.Models;
using OverlordsLauncher.Services;

namespace OverlordsLauncher.ViewModels;

public sealed class MainViewModel : INotifyPropertyChanged
{
    private readonly SettingsService _settingsService;
    private readonly SettingsImportService _importService;
    private readonly ManifestUpdateService _manifestService;
    private readonly LauncherSelfUpdateService _selfUpdateService;
    private readonly FfxiInstallDetector _detector;
    private readonly AshitaConfigGenerator _configGenerator;
    private readonly ServerStatusService _statusService;
    private readonly GameLaunchService _launchService;

    private LauncherSettings _settings;
    private LauncherManifest _manifest;
    private InstallDiagnostics _diagnostics = new();
    private ServerStatus _serverStatus = new();
    private LauncherUpdateCheckResult? _availableLauncherUpdate;

    private string _selectedTab = "Play";
    private bool _isBusy;
    private string _statusMessage = "Ready";
    private double _progressPercent;
    private int _pendingUpdatesCount;
    private string _plainPassword = string.Empty;

    public MainViewModel()
    {
        _settingsService = new SettingsService();
        _importService = new SettingsImportService();
        _manifestService = new ManifestUpdateService();
        _selfUpdateService = new LauncherSelfUpdateService();
        _detector = new FfxiInstallDetector();
        _configGenerator = new AshitaConfigGenerator();
        _statusService = new ServerStatusService();
        _launchService = new GameLaunchService();

        _manifest = _manifestService.LoadEmbeddedManifest();
        ManifestUpdateService.ApplyLocalOverride(_manifest, _settingsService.LoadLocalServerOverride());

        _settings = _settingsService.Load();
        _plainPassword = _settingsService.UnprotectPassword(_settings);

        NewsItems = new ObservableCollection<ManifestNewsItem>(_manifest.News);
        ActivityLog = new ObservableCollection<string>();

        SelectTabCommand = new RelayCommand(p => SelectedTab = p?.ToString() ?? "Play");
        PlayCommand = new AsyncRelayCommand(PlayAsync, () => !IsBusy);
        CheckUpdatesCommand = new AsyncRelayCommand(() => SyncUpdatesAsync(forceAll: false), () => !IsBusy);
        RepairFilesCommand = new AsyncRelayCommand(() => SyncUpdatesAsync(forceAll: true), () => !IsBusy);
        CheckLauncherUpdateCommand = new AsyncRelayCommand(
            () => CheckAndApplyLauncherUpdateAsync(autoApply: false, showUpToDateDialog: true),
            () => !IsBusy);
        ApplyLauncherUpdateCommand = new AsyncRelayCommand(
            ApplyAvailableLauncherUpdateAsync,
            () => !IsBusy && IsLauncherUpdateAvailable);
        InstallPrerequisitesCommand = new AsyncRelayCommand(InstallPrerequisitesAsync, () => !IsBusy);
        RefreshStatusCommand = new AsyncRelayCommand(RefreshServerStatusAsync);
        RefreshDiagnosticsCommand = new RelayCommand(RefreshDiagnostics);
        SaveSettingsCommand = new RelayCommand(SaveCurrentSettings);

        BrowseFfxiCommand = new RelayCommand(BrowseFfxiFolder);
        BrowseAshitaCommand = new RelayCommand(BrowseAshitaFolder);
        BrowseCustomDatCommand = new RelayCommand(BrowseCustomDatFolder);
        OpenAshitaFolderCommand = new RelayCommand(OpenAshitaFolder);
        ExportServerOverrideCommand = new RelayCommand(ExportShareableServerJson);
        ApplyResolutionPresetCommand = new RelayCommand(ApplyResolutionPreset);
        ImportSystemSettingsCommand = new RelayCommand(ImportSystemSettings);
        ImportAshitaIniCommand = new RelayCommand(ImportFromAshitaIniDialog);
        LaunchFfxiConfigCommand = new RelayCommand(LaunchFfxiConfigTool);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<ManifestNewsItem> NewsItems { get; }
    public ObservableCollection<string> ActivityLog { get; }

    public ICommand SelectTabCommand { get; }
    public ICommand PlayCommand { get; }
    public ICommand CheckUpdatesCommand { get; }
    public ICommand RepairFilesCommand { get; }
    public ICommand CheckLauncherUpdateCommand { get; }
    public ICommand ApplyLauncherUpdateCommand { get; }
    public ICommand InstallPrerequisitesCommand { get; }
    public ICommand RefreshStatusCommand { get; }
    public ICommand RefreshDiagnosticsCommand { get; }
    public ICommand SaveSettingsCommand { get; }
    public ICommand BrowseFfxiCommand { get; }
    public ICommand BrowseAshitaCommand { get; }
    public ICommand BrowseCustomDatCommand { get; }
    public ICommand OpenAshitaFolderCommand { get; }
    public ICommand ExportServerOverrideCommand { get; }
    public ICommand ApplyResolutionPresetCommand { get; }
    public ICommand ImportSystemSettingsCommand { get; }
    public ICommand ImportAshitaIniCommand { get; }
    public ICommand LaunchFfxiConfigCommand { get; }

    public string SelectedTab
    {
        get => _selectedTab;
        set
        {
            if (SetField(ref _selectedTab, value))
            {
                OnPropertyChanged(nameof(IsPlayTab));
                OnPropertyChanged(nameof(IsSettingsTab));
                OnPropertyChanged(nameof(IsSetupTab));
                OnPropertyChanged(nameof(IsGuideTab));
            }
        }
    }

    public bool IsPlayTab => SelectedTab == "Play";
    public bool IsSettingsTab => SelectedTab == "Settings";
    public bool IsSetupTab => SelectedTab == "Setup";
    public bool IsGuideTab => SelectedTab == "Guide";

    public string ServerName => _manifest.ServerName;
    public string Tagline => _manifest.Tagline;

    public string EffectiveHost => _settings.UseCustomServer && !string.IsNullOrWhiteSpace(_settings.CustomServerHost)
        ? _settings.CustomServerHost.Trim()
        : _manifest.DefaultHost;

    public bool EffectiveUseHairpin => _settings.UseCustomServer ? _settings.CustomUseHairpin : _manifest.UseHairpin;
    public int EffectiveLobbyPort => _settings.UseCustomServer ? _settings.CustomLobbyPort : _manifest.Ports.Lobby;
    public int EffectiveSearchPort => _settings.UseCustomServer ? _settings.CustomSearchPort : _manifest.Ports.Search;

    public bool IsBusy
    {
        get => _isBusy;
        set
        {
            if (SetField(ref _isBusy, value))
            {
                OnPropertyChanged(nameof(PlayButtonText));
                RelayCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public string PlayButtonText => IsBusy
        ? "PREPARING..."
        : PendingUpdatesCount > 0
            ? $"UPDATE & PLAY ({PendingUpdatesCount})"
            : "PLAY OVERLORDSXI";

    public string StatusMessage
    {
        get => _statusMessage;
        set => SetField(ref _statusMessage, value);
    }

    public double ProgressPercent
    {
        get => _progressPercent;
        set => SetField(ref _progressPercent, value);
    }

    public int PendingUpdatesCount
    {
        get => _pendingUpdatesCount;
        set
        {
            if (SetField(ref _pendingUpdatesCount, value))
            {
                OnPropertyChanged(nameof(PlayButtonText));
                OnPropertyChanged(nameof(UpdateBadgeText));
            }
        }
    }

    public string UpdateBadgeText => PendingUpdatesCount == 0
        ? "Client files up to date"
        : $"{PendingUpdatesCount} file update(s) ready";

    public ServerStatus ServerStatus
    {
        get => _serverStatus;
        private set => SetField(ref _serverStatus, value);
    }

    public InstallDiagnostics Diagnostics
    {
        get => _diagnostics;
        private set => SetField(ref _diagnostics, value);
    }

    public string PlainPassword
    {
        get => _plainPassword;
        set => SetField(ref _plainPassword, value);
    }

    // Settings Pass-Through Properties
    public bool UseCustomServer
    {
        get => _settings.UseCustomServer;
        set
        {
            if (_settings.UseCustomServer != value)
            {
                _settings.UseCustomServer = value;
                OnPropertyChanged();
                NotifyEffectiveServerChanged();
            }
        }
    }

    public string CustomServerHost
    {
        get => _settings.CustomServerHost;
        set
        {
            if (_settings.CustomServerHost != value)
            {
                _settings.CustomServerHost = value;
                OnPropertyChanged();
                NotifyEffectiveServerChanged();
            }
        }
    }

    public bool CustomUseHairpin
    {
        get => _settings.CustomUseHairpin;
        set
        {
            if (_settings.CustomUseHairpin != value)
            {
                _settings.CustomUseHairpin = value;
                OnPropertyChanged();
                NotifyEffectiveServerChanged();
            }
        }
    }

    public int CustomLobbyPort
    {
        get => _settings.CustomLobbyPort;
        set
        {
            if (_settings.CustomLobbyPort != value)
            {
                _settings.CustomLobbyPort = value;
                OnPropertyChanged();
                NotifyEffectiveServerChanged();
            }
        }
    }

    public int CustomSearchPort
    {
        get => _settings.CustomSearchPort;
        set
        {
            if (_settings.CustomSearchPort != value)
            {
                _settings.CustomSearchPort = value;
                OnPropertyChanged();
                NotifyEffectiveServerChanged();
            }
        }
    }

    public string FfxiPath
    {
        get => _settings.FfxiPath;
        set
        {
            if (_settings.FfxiPath != value)
            {
                _settings.FfxiPath = value;
                OnPropertyChanged();
            }
        }
    }

    public string AshitaPath
    {
        get => _settings.AshitaPath;
        set
        {
            if (_settings.AshitaPath != value)
            {
                _settings.AshitaPath = value;
                OnPropertyChanged();
            }
        }
    }

    public bool SyncToCustomDatFolder
    {
        get => _settings.SyncToCustomDatFolder;
        set
        {
            if (_settings.SyncToCustomDatFolder != value)
            {
                _settings.SyncToCustomDatFolder = value;
                OnPropertyChanged();
            }
        }
    }

    public string CustomDatOverlayPath
    {
        get => _settings.CustomDatOverlayPath;
        set
        {
            if (_settings.CustomDatOverlayPath != value)
            {
                _settings.CustomDatOverlayPath = value;
                OnPropertyChanged();
            }
        }
    }

    public string Username
    {
        get => _settings.Username;
        set
        {
            if (_settings.Username != value)
            {
                _settings.Username = value;
                OnPropertyChanged();
            }
        }
    }

    public bool RememberPassword
    {
        get => _settings.RememberPassword;
        set
        {
            if (_settings.RememberPassword != value)
            {
                _settings.RememberPassword = value;
                OnPropertyChanged();
            }
        }
    }

    public bool AutoLogin
    {
        get => _settings.AutoLogin;
        set
        {
            if (_settings.AutoLogin != value)
            {
                _settings.AutoLogin = value;
                OnPropertyChanged();
            }
        }
    }

    public IReadOnlyList<WindowModeOption> WindowModes { get; } =
    [
        WindowModeOption.Borderless,
        WindowModeOption.Windowed,
        WindowModeOption.Fullscreen
    ];

    public WindowModeOption SelectedWindowMode
    {
        get => _settings.WindowMode;
        set
        {
            if (_settings.WindowMode != value)
            {
                _settings.WindowMode = value;
                OnPropertyChanged();
            }
        }
    }

    public int WindowWidth
    {
        get => _settings.WindowWidth;
        set { if (_settings.WindowWidth != value) { _settings.WindowWidth = value; OnPropertyChanged(); } }
    }

    public int WindowHeight
    {
        get => _settings.WindowHeight;
        set { if (_settings.WindowHeight != value) { _settings.WindowHeight = value; OnPropertyChanged(); } }
    }

    public int BackgroundWidth
    {
        get => _settings.BackgroundWidth;
        set { if (_settings.BackgroundWidth != value) { _settings.BackgroundWidth = value; OnPropertyChanged(); } }
    }

    public int BackgroundHeight
    {
        get => _settings.BackgroundHeight;
        set { if (_settings.BackgroundHeight != value) { _settings.BackgroundHeight = value; OnPropertyChanged(); } }
    }

    public int MenuWidth
    {
        get => _settings.MenuWidth;
        set { if (_settings.MenuWidth != value) { _settings.MenuWidth = value; OnPropertyChanged(); } }
    }

    public int MenuHeight
    {
        get => _settings.MenuHeight;
        set { if (_settings.MenuHeight != value) { _settings.MenuHeight = value; OnPropertyChanged(); } }
    }

    public int MipMapping
    {
        get => _settings.MipMapping;
        set { if (_settings.MipMapping != value) { _settings.MipMapping = value; OnPropertyChanged(); } }
    }

    public bool BumpMapping
    {
        get => _settings.BumpMapping;
        set { if (_settings.BumpMapping != value) { _settings.BumpMapping = value; OnPropertyChanged(); } }
    }

    public bool UncompressedTextures
    {
        get => _settings.UncompressedTextures;
        set { if (_settings.UncompressedTextures != value) { _settings.UncompressedTextures = value; OnPropertyChanged(); } }
    }

    public bool UncompressedMaps
    {
        get => _settings.UncompressedMaps;
        set { if (_settings.UncompressedMaps != value) { _settings.UncompressedMaps = value; OnPropertyChanged(); } }
    }

    public bool HighQualityFonts
    {
        get => _settings.HighQualityFonts;
        set { if (_settings.HighQualityFonts != value) { _settings.HighQualityFonts = value; OnPropertyChanged(); } }
    }

    public bool HardwareMouse
    {
        get => _settings.HardwareMouse;
        set { if (_settings.HardwareMouse != value) { _settings.HardwareMouse = value; OnPropertyChanged(); } }
    }

    public bool ShowOpeningMovie
    {
        get => _settings.ShowOpeningMovie;
        set { if (_settings.ShowOpeningMovie != value) { _settings.ShowOpeningMovie = value; OnPropertyChanged(); } }
    }

    public bool SoundEnabled
    {
        get => _settings.SoundEnabled;
        set { if (_settings.SoundEnabled != value) { _settings.SoundEnabled = value; OnPropertyChanged(); } }
    }

    public bool BackgroundSound
    {
        get => _settings.BackgroundSound;
        set { if (_settings.BackgroundSound != value) { _settings.BackgroundSound = value; OnPropertyChanged(); } }
    }

    public IReadOnlyList<int> FpsCapOptions { get; } = [60, 30, 0];

    public int SelectedFpsCap
    {
        get => _settings.FpsCap;
        set { if (_settings.FpsCap != value) { _settings.FpsCap = value; OnPropertyChanged(); } }
    }

    public IReadOnlyList<string> LanguageOptions { get; } = ["US", "EU", "JP"];

    public string SelectedLanguage
    {
        get => _settings.Language;
        set { if (_settings.Language != value) { _settings.Language = value; OnPropertyChanged(); } }
    }

    public bool EnablePivotOverlay
    {
        get => _settings.EnablePivotOverlay;
        set { if (_settings.EnablePivotOverlay != value) { _settings.EnablePivotOverlay = value; OnPropertyChanged(); } }
    }

    public bool AutoLoadTalentsAddon
    {
        get => _settings.AutoLoadTalentsAddon;
        set { if (_settings.AutoLoadTalentsAddon != value) { _settings.AutoLoadTalentsAddon = value; OnPropertyChanged(); } }
    }

    public bool AutoLoadCrystalSocketAddon
    {
        get => _settings.AutoLoadCrystalSocketAddon;
        set { if (_settings.AutoLoadCrystalSocketAddon != value) { _settings.AutoLoadCrystalSocketAddon = value; OnPropertyChanged(); } }
    }

    public bool AutoCloseOnLaunch
    {
        get => _settings.AutoCloseOnLaunch;
        set { if (_settings.AutoCloseOnLaunch != value) { _settings.AutoCloseOnLaunch = value; OnPropertyChanged(); } }
    }

    public bool AutoCheckUpdatesOnStartup
    {
        get => _settings.AutoCheckUpdatesOnStartup;
        set { if (_settings.AutoCheckUpdatesOnStartup != value) { _settings.AutoCheckUpdatesOnStartup = value; OnPropertyChanged(); } }
    }

    public bool AutoUpdateLauncher
    {
        get => _settings.AutoUpdateLauncher;
        set { if (_settings.AutoUpdateLauncher != value) { _settings.AutoUpdateLauncher = value; OnPropertyChanged(); } }
    }

    public string LauncherVersionText => $"v{LauncherSelfUpdateService.GetCurrentVersion()}";

    public bool IsLauncherUpdateAvailable => _availableLauncherUpdate?.UpdateAvailable == true;

    public string LauncherUpdateButtonText => IsLauncherUpdateAvailable
        ? $"Update Launcher ({_availableLauncherUpdate!.LatestTag})"
        : "Check Launcher Update";

    public bool GamepadAllowBackground
    {
        get => _settings.GamepadAllowBackground;
        set { if (_settings.GamepadAllowBackground != value) { _settings.GamepadAllowBackground = value; OnPropertyChanged(); } }
    }

    public bool GamepadDisableEnumeration
    {
        get => _settings.GamepadDisableEnumeration;
        set { if (_settings.GamepadDisableEnumeration != value) { _settings.GamepadDisableEnumeration = value; OnPropertyChanged(); } }
    }

    public bool EnableGamepad
    {
        get => _settings.EnableGamepad;
        set
        {
            if (_settings.EnableGamepad != value)
            {
                _settings.EnableGamepad = value;
                _settings.UseCustomGamepadConfig = true;
                OnPropertyChanged();
                OnPropertyChanged(nameof(GamepadSummaryText));
            }
        }
    }

    public bool EnableXInput
    {
        get => _settings.EnableXInput;
        set
        {
            if (_settings.EnableXInput != value)
            {
                _settings.EnableXInput = value;
                _settings.UseCustomGamepadConfig = true;
                OnPropertyChanged();
                OnPropertyChanged(nameof(GamepadSummaryText));
            }
        }
    }

    public string GamepadSummaryText
    {
        get
        {
            var padMode = AshitaConfigGenerator.BuildEffectivePadMode(_settings);
            var hasCustomMap = !string.IsNullOrWhiteSpace(_settings.PadSin);
            if (padMode == "-1" && !hasCustomMap)
            {
                return "Gamepad mode: Windows FFXI Registry passthrough (-1)";
            }

            var mappingLabel = hasCustomMap ? "button map imported" : "default button map";
            return $"padmode000 = {padMode} ({mappingLabel})";
        }
    }

    public string ImportedSettingsSourceText =>
        string.IsNullOrWhiteSpace(_settings.ImportedSettingsSource)
            ? "No external FFXI/Ashita settings imported yet"
            : $"Last imported: {_settings.ImportedSettingsSource}";

    public async Task InitializeAsync()
    {
        var justUpdated = Environment.GetCommandLineArgs()
            .Any(arg => arg.Equals(LauncherSelfUpdateService.JustUpdatedArg, StringComparison.OrdinalIgnoreCase));
        LauncherSelfUpdateService.CleanupStagingDirectory();

        var isFirstRun = !File.Exists(_settingsService.SettingsPath);
        RefreshDiagnostics();
        if (string.IsNullOrWhiteSpace(_settings.FfxiPath) && !string.IsNullOrWhiteSpace(Diagnostics.DetectedFfxiPath))
        {
            FfxiPath = Diagnostics.DetectedFfxiPath;
            if (Diagnostics.FfxiRegion is "US" or "EU" or "JP")
            {
                SelectedLanguage = Diagnostics.FfxiRegion;
            }
        }

        if (isFirstRun || !_settings.HasImportedSystemSettings)
        {
            var importResult = _importService.ImportBestAvailable(_settings, gamepadOnly: !isFirstRun);
            if (importResult.ImportedAny)
            {
                NotifyAllSettingsChanged();
                _settingsService.Save(_settings, PlainPassword);
                Log(importResult.SourceSummary);
            }
            else if (isFirstRun)
            {
                _settings.HasImportedSystemSettings = true;
                _settingsService.Save(_settings, PlainPassword);
            }
        }

        Log($"Launcher {LauncherVersionText} initialized. Ashita path: {AshitaPath}");
        if (justUpdated)
        {
            StatusMessage = $"Launcher updated to {LauncherVersionText}.";
            Log(StatusMessage);
        }

        await RefreshServerStatusAsync();

        if (_settings.AutoCheckUpdatesOnStartup)
        {
            await CheckUpdatesOnlyAsync();
        }

        if (!justUpdated && (_settings.AutoUpdateLauncher || _settings.AutoCheckUpdatesOnStartup))
        {
            await CheckAndApplyLauncherUpdateAsync(autoApply: _settings.AutoUpdateLauncher, showUpToDateDialog: false);
        }
    }

    private async Task CheckUpdatesOnlyAsync()
    {
        try
        {
            StatusMessage = "Checking OverlordsXI manifest...";
            var embedded = _manifestService.LoadEmbeddedManifest();
            var (manifest, fromRemote) = await _manifestService.FetchManifestAsync(
                embedded,
                _settingsService.LoadLocalServerOverride());

            _manifest = manifest;
            OnPropertyChanged(nameof(ServerName));
            OnPropertyChanged(nameof(Tagline));
            NotifyEffectiveServerChanged();

            NewsItems.Clear();
            foreach (var item in _manifest.News)
            {
                NewsItems.Add(item);
            }

            var pending = _manifestService.GetOutdatedFiles(_manifest, _settings);
            PendingUpdatesCount = pending.Count;
            RefreshDiagnostics();

            StatusMessage = fromRemote
                ? (pending.Count == 0 ? "All OverlordsXI client files are up to date." : $"{pending.Count} update(s) available.")
                : "Using bundled manifest (offline or GitHub unreachable).";
            Log(StatusMessage);
        }
        catch (Exception ex)
        {
            StatusMessage = $"Update check failed: {ex.Message}";
            Log(StatusMessage);
        }
    }

    private async Task CheckAndApplyLauncherUpdateAsync(bool autoApply, bool showUpToDateDialog)
    {
        try
        {
            var result = await _selfUpdateService.CheckForUpdateAsync(_manifest);
            _availableLauncherUpdate = result;
            OnPropertyChanged(nameof(IsLauncherUpdateAvailable));
            OnPropertyChanged(nameof(LauncherUpdateButtonText));
            RelayCommand.RaiseCanExecuteChanged();

            if (!result.UpdateAvailable)
            {
                if (showUpToDateDialog)
                {
                    MessageBox.Show(
                        $"OverlordsXI Launcher {LauncherVersionText} is already up to date.",
                        "Launcher Up to Date",
                        MessageBoxButton.OK,
                        MessageBoxImage.Information);
                }

                return;
            }

            Log($"Launcher update available: {result.LatestTag} (current {LauncherVersionText})");

            if (autoApply && !IsBusy)
            {
                if (LauncherSelfUpdateService.CanSelfUpdateInPlace(out _, out var reason))
                {
                    await ApplyAvailableLauncherUpdateAsync();
                    return;
                }

                Log($"Automatic launcher update skipped: {reason}");
                StatusMessage = $"Launcher {result.LatestTag} available (click Update Launcher).";
                return;
            }

            StatusMessage = $"Launcher {result.LatestTag} is available!";
            if (showUpToDateDialog)
            {
                var choice = MessageBox.Show(
                    $"A new OverlordsXI Launcher release ({result.LatestTag}) is available.\nCurrent version: {LauncherVersionText}\n\nDownload and restart now?",
                    "Launcher Update Available",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Information);
                if (choice == MessageBoxResult.Yes)
                {
                    await ApplyAvailableLauncherUpdateAsync();
                }
            }
        }
        catch (Exception ex)
        {
            Log($"Launcher update check skipped: {ex.Message}");
            if (showUpToDateDialog)
            {
                MessageBox.Show(
                    $"Could not check GitHub Releases for launcher updates:\n{ex.Message}",
                    "Launcher Update Check Failed",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
            }
        }
    }

    private async Task ApplyAvailableLauncherUpdateAsync()
    {
        if (_availableLauncherUpdate is null || !_availableLauncherUpdate.UpdateAvailable)
        {
            return;
        }

        if (!LauncherSelfUpdateService.CanSelfUpdateInPlace(out var targetExePath, out var reason) ||
            string.IsNullOrEmpty(targetExePath))
        {
            Log(reason);
            if (!string.IsNullOrWhiteSpace(_availableLauncherUpdate.ReleaseUrl))
            {
                var openBrowser = MessageBox.Show(
                    $"{reason}\n\nOpen the GitHub Release page to download {_availableLauncherUpdate.LatestTag}?",
                    "Manual Update Required",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Information);
                if (openBrowser == MessageBoxResult.Yes)
                {
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = _availableLauncherUpdate.ReleaseUrl,
                        UseShellExecute = true
                    });
                }
            }

            return;
        }

        IsBusy = true;
        ProgressPercent = 0;
        try
        {
            var progress = new Progress<SyncProgress>(p =>
            {
                StatusMessage = p.Message;
                ProgressPercent = p.Percent;
            });

            Log($"Downloading launcher update {_availableLauncherUpdate.LatestTag}...");
            var stagedExe = await _selfUpdateService.DownloadUpdateAsync(_availableLauncherUpdate, progress);
            StatusMessage = $"Installing {_availableLauncherUpdate.LatestTag} and restarting...";
            Log(StatusMessage);

            _selfUpdateService.LaunchUpdaterAndPrepareRestart(stagedExe, targetExePath);
            Application.Current?.Shutdown();
        }
        catch (Exception ex)
        {
            StatusMessage = $"Launcher self-update failed: {ex.Message}";
            Log(StatusMessage);
            MessageBox.Show(
                $"Could not update OverlordsLauncher.exe:\n{ex.Message}",
                "Launcher Update Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
        finally
        {
            IsBusy = false;
        }
    }

    private async Task SyncUpdatesAsync(bool forceAll)
    {
        IsBusy = true;
        ProgressPercent = 0;
        try
        {
            var embedded = _manifestService.LoadEmbeddedManifest();
            var (manifest, _) = await _manifestService.FetchManifestAsync(
                embedded,
                _settingsService.LoadLocalServerOverride());
            _manifest = manifest;

            var progress = new Progress<SyncProgress>(p =>
            {
                StatusMessage = p.Message;
                ProgressPercent = p.Percent;
            });

            var count = await _manifestService.SyncOverlordsFilesAsync(_manifest, _settings, forceAll, progress);
            PendingUpdatesCount = _manifestService.GetOutdatedFiles(_manifest, _settings).Count;
            RefreshDiagnostics();

            Log(count > 0 ? $"Updated {count} OverlordsXI client file(s)." : "No file updates required.");
        }
        catch (Exception ex)
        {
            StatusMessage = $"Sync error: {ex.Message}";
            Log(StatusMessage);
            MessageBox.Show(ex.Message, "OverlordsXI Sync Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            IsBusy = false;
        }
    }

    private async Task InstallPrerequisitesAsync()
    {
        IsBusy = true;
        ProgressPercent = 0;
        try
        {
            var progress = new Progress<SyncProgress>(p =>
            {
                StatusMessage = p.Message;
                ProgressPercent = p.Percent;
            });

            await _manifestService.EnsureAshitaAndToolsAsync(_manifest, _settings, progress);
            await _manifestService.SyncOverlordsFilesAsync(_manifest, _settings, forceAll: false, progress);
            PendingUpdatesCount = _manifestService.GetOutdatedFiles(_manifest, _settings).Count;
            RefreshDiagnostics();
            Log("Ashita v4, xiloader, XIPivot, and OverlordsXI files are ready.");
        }
        catch (Exception ex)
        {
            StatusMessage = $"Setup error: {ex.Message}";
            Log(StatusMessage);
            MessageBox.Show(ex.Message, "OverlordsXI Setup Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            IsBusy = false;
        }
    }

    private async Task PlayAsync()
    {
        if (_settings.AutoLogin && (string.IsNullOrWhiteSpace(_settings.Username) || string.IsNullOrEmpty(PlainPassword)))
        {
            MessageBox.Show(
                "Auto-login is enabled, so please enter both a username and password (or uncheck Auto-login to use the xiloader prompt).",
                "Missing Credentials",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        IsBusy = true;
        ProgressPercent = 0;

        try
        {
            _settingsService.Save(_settings, PlainPassword);

            var progress = new Progress<SyncProgress>(p =>
            {
                StatusMessage = p.Message;
                ProgressPercent = p.Percent;
            });

            StatusMessage = "Checking Ashita v4 prerequisites...";
            await _manifestService.EnsureAshitaAndToolsAsync(_manifest, _settings, progress);

            StatusMessage = "Checking OverlordsXI files...";
            var embedded = _manifestService.LoadEmbeddedManifest();
            var (manifest, _) = await _manifestService.FetchManifestAsync(
                embedded,
                _settingsService.LoadLocalServerOverride());
            _manifest = manifest;

            await _manifestService.SyncOverlordsFilesAsync(_manifest, _settings, forceAll: false, progress);
            PendingUpdatesCount = _manifestService.GetOutdatedFiles(_manifest, _settings).Count;

            var xiloaderPath = FfxiInstallDetector.ResolveXiloaderPath(_settings.AshitaPath);
            if (string.IsNullOrEmpty(xiloaderPath))
            {
                throw new FileNotFoundException("xiloader.exe could not be located or downloaded.");
            }

            StatusMessage = "Writing Ashita v4 & Pivot configurations...";
            _configGenerator.WriteAllConfigs(
                _settings.AshitaPath,
                _settings,
                EffectiveHost,
                EffectiveUseHairpin,
                PlainPassword,
                xiloaderPath);

            RefreshDiagnostics();

            StatusMessage = $"Launching Ashita v4 -> {EffectiveHost}...";
            Log(StatusMessage);
            _launchService.LaunchAshita(_settings.AshitaPath);

            if (_settings.AutoCloseOnLaunch)
            {
                Application.Current.Shutdown();
            }
        }
        catch (Exception ex)
        {
            StatusMessage = $"Launch failed: {ex.Message}";
            Log(StatusMessage);
            MessageBox.Show(ex.Message, "Launch Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            IsBusy = false;
        }
    }

    private async Task RefreshServerStatusAsync()
    {
        ServerStatus = new ServerStatus
        {
            Host = EffectiveHost,
            IsOnline = false,
            SummaryText = $"Checking {EffectiveHost}..."
        };

        var result = await _statusService.CheckAsync(EffectiveHost, EffectiveLobbyPort, EffectiveSearchPort);
        ServerStatus = result;
    }

    private void RefreshDiagnostics()
    {
        Diagnostics = _detector.Inspect(_settings, _manifest);
        PendingUpdatesCount = _manifestService.GetOutdatedFiles(_manifest, _settings).Count;
    }

    private void SaveCurrentSettings()
    {
        _settingsService.Save(_settings, PlainPassword);
        StatusMessage = "Settings saved.";
        Log($"Settings saved to {_settingsService.SettingsPath}");
        _ = RefreshServerStatusAsync();
    }

    private void BrowseFfxiFolder()
    {
        var dialog = new OpenFolderDialog
        {
            Title = "Select FINAL FANTASY XI Installation Folder",
            InitialDirectory = Directory.Exists(FfxiPath) ? FfxiPath : @"C:\"
        };
        if (dialog.ShowDialog() == true)
        {
            FfxiPath = dialog.FolderName;
            RefreshDiagnostics();
        }
    }

    private void BrowseAshitaFolder()
    {
        var dialog = new OpenFolderDialog
        {
            Title = "Select Ashita v4 Folder",
            InitialDirectory = Directory.Exists(AshitaPath) ? AshitaPath : AppContext.BaseDirectory
        };
        if (dialog.ShowDialog() == true)
        {
            AshitaPath = dialog.FolderName;
            RefreshDiagnostics();
        }
    }

    private void BrowseCustomDatFolder()
    {
        var dialog = new OpenFolderDialog
        {
            Title = "Select Custom DAT Overlay Folder",
            InitialDirectory = Directory.Exists(CustomDatOverlayPath) ? CustomDatOverlayPath : @"C:\"
        };
        if (dialog.ShowDialog() == true)
        {
            CustomDatOverlayPath = dialog.FolderName;
        }
    }

    private void OpenAshitaFolder()
    {
        Directory.CreateDirectory(AshitaPath);
        Process.Start(new ProcessStartInfo
        {
            FileName = AshitaPath,
            UseShellExecute = true
        });
    }

    private void ExportShareableServerJson()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "overlords-server.json");
        var payload = new LocalServerOverride
        {
            ServerName = _manifest.ServerName,
            DefaultHost = EffectiveHost,
            UseHairpin = EffectiveUseHairpin,
            LobbyPort = EffectiveLobbyPort,
            SearchPort = EffectiveSearchPort
        };

        var json = JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(path, json);
        StatusMessage = $"Exported {path}";
        Log($"Exported shareable server config: {path}");
        MessageBox.Show(
            $"Saved server config to:\n{path}\n\nDistribute OverlordsLauncher.exe alongside this file so players automatically connect to {EffectiveHost}.",
            "Shareable Config Exported",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private void ApplyResolutionPreset(object? parameter)
    {
        var preset = parameter?.ToString();
        switch (preset)
        {
            case "1080p":
                WindowWidth = 1920;
                WindowHeight = 1080;
                MenuWidth = 1920;
                MenuHeight = 1080;
                BackgroundWidth = 2048;
                BackgroundHeight = 2048;
                break;
            case "1440p":
                WindowWidth = 2560;
                WindowHeight = 1440;
                MenuWidth = 1920;
                MenuHeight = 1080;
                BackgroundWidth = 4096;
                BackgroundHeight = 4096;
                break;
            case "4k":
                WindowWidth = 3840;
                WindowHeight = 2160;
                MenuWidth = 1920;
                MenuHeight = 1080;
                BackgroundWidth = 4096;
                BackgroundHeight = 4096;
                break;
            case "720p":
                WindowWidth = 1280;
                WindowHeight = 720;
                MenuWidth = 1280;
                MenuHeight = 720;
                BackgroundWidth = 2048;
                BackgroundHeight = 2048;
                break;
        }
    }

    private void ImportSystemSettings()
    {
        var result = _importService.ImportBestAvailable(_settings, gamepadOnly: false);
        NotifyAllSettingsChanged();

        if (result.ImportedAny)
        {
            _settingsService.Save(_settings, PlainPassword);
            StatusMessage = result.SourceSummary;
            Log(result.SourceSummary);
            RefreshDiagnostics();
            MessageBox.Show(
                $"{result.SourceSummary}\n\nGamepad: {GamepadSummaryText}\nResolution: {WindowWidth}x{WindowHeight} ({SelectedWindowMode})",
                "Settings Imported",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
        }
        else
        {
            StatusMessage = result.SourceSummary;
            Log(result.SourceSummary);
            MessageBox.Show(
                "Could not find existing settings in Windows FFXI Registry or standard Ashita config folders.\n\nUse \"Import Ashita .ini...\" to select your existing Ashita boot .ini file manually, or click \"Open FFXI Config\" to configure your gamepad.",
                "No Existing Settings Found",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
        }
    }

    private void ImportFromAshitaIniDialog()
    {
        var dialog = new OpenFileDialog
        {
            Title = "Select Existing Ashita v4 Boot Configuration (.ini)",
            Filter = "Ashita INI Files (*.ini)|*.ini|All Files (*.*)|*.*",
            InitialDirectory = Directory.Exists(Path.Combine(AshitaPath, "config", "boot"))
                ? Path.Combine(AshitaPath, "config", "boot")
                : AppContext.BaseDirectory
        };

        if (dialog.ShowDialog() == true)
        {
            if (_importService.TryImportFromAshitaIni(dialog.FileName, _settings, gamepadOnly: false))
            {
                NotifyAllSettingsChanged();
                _settingsService.Save(_settings, PlainPassword);
                StatusMessage = $"Imported settings from {Path.GetFileName(dialog.FileName)}";
                Log($"Imported settings from {dialog.FileName}");
                RefreshDiagnostics();
            }
            else
            {
                MessageBox.Show(
                    "No FFXI registry or Ashita input settings were found inside the selected .ini file.",
                    "Import Unchanged",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
            }
        }
    }

    private void LaunchFfxiConfigTool()
    {
        var exe = SettingsImportService.FindFfxiConfigExecutable(_settings);
        if (string.IsNullOrEmpty(exe))
        {
            MessageBox.Show(
                "Could not locate FINAL FANTASY XI Config.exe or FFXiPadConfig.exe inside your FFXI folder.",
                "FFXI Config Tool Not Found",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        Process.Start(new ProcessStartInfo
        {
            FileName = exe,
            WorkingDirectory = Path.GetDirectoryName(exe) ?? string.Empty,
            UseShellExecute = true
        });
        Log($"Opened {Path.GetFileName(exe)} — click 'Auto-Import Current Settings' after saving changes.");
    }

    private void NotifyAllSettingsChanged()
    {
        OnPropertyChanged(nameof(FfxiPath));
        OnPropertyChanged(nameof(SelectedWindowMode));
        OnPropertyChanged(nameof(WindowWidth));
        OnPropertyChanged(nameof(WindowHeight));
        OnPropertyChanged(nameof(BackgroundWidth));
        OnPropertyChanged(nameof(BackgroundHeight));
        OnPropertyChanged(nameof(MenuWidth));
        OnPropertyChanged(nameof(MenuHeight));
        OnPropertyChanged(nameof(MipMapping));
        OnPropertyChanged(nameof(BumpMapping));
        OnPropertyChanged(nameof(UncompressedTextures));
        OnPropertyChanged(nameof(UncompressedMaps));
        OnPropertyChanged(nameof(HighQualityFonts));
        OnPropertyChanged(nameof(HardwareMouse));
        OnPropertyChanged(nameof(ShowOpeningMovie));
        OnPropertyChanged(nameof(SoundEnabled));
        OnPropertyChanged(nameof(BackgroundSound));
        OnPropertyChanged(nameof(SelectedLanguage));
        OnPropertyChanged(nameof(GamepadAllowBackground));
        OnPropertyChanged(nameof(GamepadDisableEnumeration));
        OnPropertyChanged(nameof(EnableGamepad));
        OnPropertyChanged(nameof(EnableXInput));
        OnPropertyChanged(nameof(GamepadSummaryText));
        OnPropertyChanged(nameof(ImportedSettingsSourceText));
    }

    private void NotifyEffectiveServerChanged()
    {
        OnPropertyChanged(nameof(EffectiveHost));
        OnPropertyChanged(nameof(EffectiveUseHairpin));
        OnPropertyChanged(nameof(EffectiveLobbyPort));
        OnPropertyChanged(nameof(EffectiveSearchPort));
    }

    private void Log(string message)
    {
        var line = $"[{DateTime.Now:HH:mm:ss}] {message}";
        if (Application.Current?.Dispatcher is { } dispatcher && !dispatcher.CheckAccess())
        {
            dispatcher.Invoke(() => ActivityLog.Insert(0, line));
        }
        else
        {
            ActivityLog.Insert(0, line);
        }
    }

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }

        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
