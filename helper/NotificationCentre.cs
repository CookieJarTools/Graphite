using Windows.UI.Notifications;
using Windows.UI.Notifications.Management;
using Windows.Storage.Streams;

namespace WinKeyHelper;

/// <summary>
/// Windows' own notifications (what its notification centre holds), for the calendar panel:
/// read through the notification listener, which Windows lets an ordinary desktop program use
/// once allowed. "notifications" reports them, "notifications dismiss id" and
/// "notifications clear" take them away, from Windows too.
///
/// Windows takes a couple of seconds to list them and tells an unpackaged program nothing
/// when they change, so main.js asks every few seconds and keeps the latest list. A
/// notification's details are read once, when first seen, and kept by its id.
/// </summary>
internal static class NotificationCentre
{
    private const int MostShown = 50;
    private static readonly SemaphoreSlim OneAtATime = new(1, 1);
    private static readonly Dictionary<uint, object?> Described = new(); // notification id -> what the panel shows (null: nothing to show)
    private static readonly Dictionary<string, string?> Logos = new(); // app id -> data URL
    private static UserNotificationListener? _listener;

    public static void Command(string arg)
    {
        Task.Run(async () =>
        {
            // Polls can pile up behind a slow read; the waiting ones are simply dropped.
            if (arg.Length == 0 && OneAtATime.CurrentCount == 0) return;
            await OneAtATime.WaitAsync();
            try
            {
                var listener = await Listener();
                if (listener is null)
                {
                    Program.Emit(new { @event = "notifications", allowed = false, items = Array.Empty<object>() });
                    return;
                }
                if (arg == "clear") listener.ClearNotifications();
                else if (arg.StartsWith("dismiss ") && uint.TryParse(arg[8..], out uint id)) listener.RemoveNotification(id);
                await Report(listener);
            }
            catch (Exception error)
            {
                Program.Emit(new { @event = "log", message = "notifications: " + error.Message });
            }
            finally
            {
                OneAtATime.Release();
            }
        });
    }

    private static async Task<UserNotificationListener?> Listener()
    {
        if (_listener is not null) return _listener;
        var listener = UserNotificationListener.Current;
        if (await listener.RequestAccessAsync() != UserNotificationListenerAccessStatus.Allowed) return null;
        return _listener = listener;
    }

    private static async Task Report(UserNotificationListener listener)
    {
        var notifications = await listener.GetNotificationsAsync(NotificationKinds.Toast);
        var present = new HashSet<uint>();
        var items = new List<object>();
        foreach (var notification in notifications.OrderByDescending((item) => item.CreationTime).Take(MostShown))
        {
            present.Add(notification.Id);
            if (!Described.TryGetValue(notification.Id, out var described))
            {
                described = await Describe(notification);
                Described[notification.Id] = described;
            }
            if (described is not null) items.Add(described);
        }
        foreach (uint gone in Described.Keys.Where((id) => !present.Contains(id)).ToList()) Described.Remove(gone);
        Program.Emit(new { @event = "notifications", allowed = true, items });
    }

    private static async Task<object?> Describe(UserNotification notification)
    {
        var texts = Texts(notification);
        if (texts.Count == 0) return null;
        string appId = "", appName = "";
        try
        {
            appId = notification.AppInfo.AppUserModelId;
            appName = notification.AppInfo.DisplayInfo.DisplayName;
        }
        catch
        {
            // Some senders have no app details to give.
        }
        return new
        {
            id = notification.Id,
            appId,
            app = appName,
            icon = await Logo(notification, appId),
            title = texts[0],
            body = string.Join("\n", texts.Skip(1)),
            time = notification.CreationTime.ToUnixTimeMilliseconds(),
        };
    }

    private static List<string> Texts(UserNotification notification)
    {
        try
        {
            var binding = notification.Notification.Visual.GetBinding(KnownNotificationBindings.ToastGeneric);
            return binding?.GetTextElements().Select((element) => element.Text.Trim()).Where((text) => text.Length > 0).ToList() ?? new List<string>();
        }
        catch
        {
            return new List<string>();
        }
    }

    // The app's logo as a data URL, read once per app.
    private static async Task<string?> Logo(UserNotification notification, string appId)
    {
        if (Logos.TryGetValue(appId, out var cached)) return cached;
        string? url = null;
        try
        {
            var reference = notification.AppInfo.DisplayInfo.GetLogo(new Windows.Foundation.Size(32, 32));
            using var stream = await reference.OpenReadAsync();
            if (stream.Size > 0 && stream.Size < 1_000_000)
            {
                var buffer = new Windows.Storage.Streams.Buffer((uint)stream.Size);
                var read = await stream.ReadAsync(buffer, (uint)stream.Size, InputStreamOptions.None);
                var bytes = new byte[read.Length];
                DataReader.FromBuffer(read).ReadBytes(bytes);
                url = "data:" + (string.IsNullOrEmpty(stream.ContentType) ? "image/png" : stream.ContentType) + ";base64," + Convert.ToBase64String(bytes);
            }
        }
        catch
        {
            // No logo: the panel shows the app's initial.
        }
        Logos[appId] = url;
        return url;
    }
}
