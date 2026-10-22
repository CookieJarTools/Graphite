using System.Runtime.InteropServices;
using Windows.Devices.Radios;
using Windows.Media.Control;
using Windows.Storage.Streams;

namespace WinKeyHelper;

/// <summary>
/// What the quick-settings panel shows and changes: the speaker volume (Core Audio), the
/// Wi-Fi and Bluetooth radios, and whatever media is playing. "system" reports it all as
/// one event; the other commands change one thing and report again.
/// </summary>
internal static class SystemControls
{
    private static GlobalSystemMediaTransportControlsSessionManager? _media;
    private static string _lastArtKey = "";
    private static string? _lastArt;

    public static void Report() => Run(ReportAsync);

    public static void SetVolume(string arg)
    {
        if (!int.TryParse(arg, out int percent)) return;
        Run(async () =>
        {
            WithSpeakers(speakers =>
            {
                var context = Guid.Empty;
                speakers.SetMasterVolumeLevelScalar(Math.Clamp(percent, 0, 100) / 100f, ref context);
                if (percent > 0) speakers.SetMute(false, ref context);
            });
            await ReportAsync();
        });
    }

    public static void SetMute(string arg) => Run(async () =>
    {
        WithSpeakers(speakers =>
        {
            var context = Guid.Empty;
            speakers.SetMute(arg == "1", ref context);
        });
        await ReportAsync();
    });

    // "wifi 1", "bluetooth 0"
    public static void SetRadio(string arg) => Run(async () =>
    {
        var parts = arg.Split(' ');
        if (parts.Length != 2) return;
        var kind = parts[0] == "wifi" ? RadioKind.WiFi : parts[0] == "bluetooth" ? RadioKind.Bluetooth : RadioKind.Other;
        if (kind == RadioKind.Other) return;
        if (await Radio.RequestAccessAsync() != RadioAccessStatus.Allowed) return;
        foreach (var radio in await Radio.GetRadiosAsync())
        {
            if (radio.Kind == kind) await radio.SetStateAsync(parts[1] == "1" ? RadioState.On : RadioState.Off);
        }
        await ReportAsync();
    });

    // "playpause", "next", "previous"
    public static void Media(string arg) => Run(async () =>
    {
        var session = (await MediaManager())?.GetCurrentSession();
        if (session is null) return;
        _ = arg switch
        {
            "playpause" => await session.TryTogglePlayPauseAsync(),
            "next" => await session.TrySkipNextAsync(),
            "previous" => await session.TrySkipPreviousAsync(),
            _ => false,
        };
        await Task.Delay(250); // the new state takes a moment to show
        await ReportAsync();
    });

    private static async Task ReportAsync()
    {
        float volume = 0;
        bool muted = false, haveSpeakers = WithSpeakers(speakers =>
        {
            speakers.GetMasterVolumeLevelScalar(out volume);
            speakers.GetMute(out muted);
        });

        bool? wifi = null, bluetooth = null;
        try
        {
            if (await Radio.RequestAccessAsync() == RadioAccessStatus.Allowed)
            {
                foreach (var radio in await Radio.GetRadiosAsync())
                {
                    if (radio.Kind == RadioKind.WiFi) wifi = (wifi ?? false) || radio.State == RadioState.On;
                    if (radio.Kind == RadioKind.Bluetooth) bluetooth = (bluetooth ?? false) || radio.State == RadioState.On;
                }
            }
        }
        catch
        {
            // No radio access: the tiles show as unavailable.
        }

        Program.Emit(new
        {
            @event = "system",
            speakers = haveSpeakers ? new { volume = (int)Math.Round(volume * 100), muted } : null,
            wifi,
            bluetooth,
            media = await DescribeMedia(),
        });
    }

    private static async Task<object?> DescribeMedia()
    {
        try
        {
            var session = (await MediaManager())?.GetCurrentSession();
            if (session is null) return null;
            var properties = await session.TryGetMediaPropertiesAsync();
            var playback = session.GetPlaybackInfo();
            if (properties is null || string.IsNullOrEmpty(properties.Title)) return null;
            return new
            {
                title = properties.Title,
                artist = properties.Artist,
                app = session.SourceAppUserModelId,
                playing = playback.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing,
                canPrevious = playback.Controls.IsPreviousEnabled,
                canNext = playback.Controls.IsNextEnabled,
                art = await ArtOf(properties),
            };
        }
        catch
        {
            return null;
        }
    }

    // Cover art as a data URL, read once per track.
    private static async Task<string?> ArtOf(GlobalSystemMediaTransportControlsSessionMediaProperties properties)
    {
        string key = properties.Title + "\n" + properties.Artist + "\n" + properties.AlbumTitle;
        if (key == _lastArtKey) return _lastArt;
        _lastArtKey = key;
        _lastArt = null;
        if (properties.Thumbnail is null) return null;
        using var stream = await properties.Thumbnail.OpenReadAsync();
        if (stream.Size == 0 || stream.Size > 2_000_000) return null;
        var buffer = new Windows.Storage.Streams.Buffer((uint)stream.Size);
        var read = await stream.ReadAsync(buffer, (uint)stream.Size, InputStreamOptions.None);
        var bytes = new byte[read.Length];
        DataReader.FromBuffer(read).ReadBytes(bytes);
        _lastArt = "data:" + (string.IsNullOrEmpty(stream.ContentType) ? "image/png" : stream.ContentType) + ";base64," + Convert.ToBase64String(bytes);
        return _lastArt;
    }

    private static async Task<GlobalSystemMediaTransportControlsSessionManager?> MediaManager()
    {
        try
        {
            return _media ??= await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
        }
        catch
        {
            return null;
        }
    }

    // Off the input thread; a failure only means the panel shows less.
    private static void Run(Func<Task> work) => Task.Run(async () =>
    {
        try
        {
            await work();
        }
        catch (Exception error)
        {
            Program.Emit(new { @event = "log", message = "system controls: " + error.Message });
        }
    });

    // ---------- Core Audio ----------

    private static bool WithSpeakers(Action<IAudioEndpointVolume> use)
    {
        try
        {
            var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
            if (enumerator.GetDefaultAudioEndpoint(0 /* render */, 1 /* multimedia */, out var device) != 0) return false;
            var iid = typeof(IAudioEndpointVolume).GUID;
            if (device.Activate(ref iid, 23 /* CLSCTX_ALL */, IntPtr.Zero, out var volume) != 0) return false;
            use((IAudioEndpointVolume)volume);
            return true;
        }
        catch
        {
            return false; // no output device
        }
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    private class MMDeviceEnumerator
    {
    }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object anInterface);
    }

    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioEndpointVolume
    {
        [PreserveSig] int RegisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int UnregisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int GetChannelCount(out uint count);
        [PreserveSig] int SetMasterVolumeLevel(float levelDb, ref Guid context);
        [PreserveSig] int SetMasterVolumeLevelScalar(float level, ref Guid context);
        [PreserveSig] int GetMasterVolumeLevel(out float levelDb);
        [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
        [PreserveSig] int SetChannelVolumeLevel(uint channel, float levelDb, ref Guid context);
        [PreserveSig] int SetChannelVolumeLevelScalar(uint channel, float level, ref Guid context);
        [PreserveSig] int GetChannelVolumeLevel(uint channel, out float levelDb);
        [PreserveSig] int GetChannelVolumeLevelScalar(uint channel, out float level);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid context);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }
}
