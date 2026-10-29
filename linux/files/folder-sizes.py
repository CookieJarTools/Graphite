# Graphite Desk: a Size column in Files (Nautilus) that gives folders their size too, as the
# space everything in them takes, where Files itself shows only how many items a folder holds;
# a drive (one connected, or the links in the Drives place: drives.sh) shows the space left on
# it, with a bar.
# A folder is measured on a thread of its own (two at a time, so a hard drive isn't swamped),
# showing "Calculating..." meanwhile, and Files is told to ask again once its size is known (it
# would otherwise wait for each folder before the next); the answer is kept for a few minutes,
# or until the folder changes. apps/register.sh links this into
# ~/.local/share/nautilus-python/extensions and makes it the list view's Size column; it needs
# Arch's nautilus-python.
import os
import threading
import time

from gi.repository import GLib, GObject, Nautilus

KEPT_FOR = 300  # seconds an answer is trusted
measuring = threading.Semaphore(2)
answers = {}  # path: (seconds, folder's mtime, bytes)
measured = set()  # paths being measured now
lock = threading.Lock()


# "■■■■■■□□□□  412.3 GB free of 1.0 TB": the bar is the part used.
def drive_space(path):
    try:
        disk = os.statvfs(path)
    except OSError:
        return None
    total = disk.f_blocks * disk.f_frsize
    free = disk.f_bavail * disk.f_frsize
    if total <= 0:
        return None
    used = round(10 * (total - free) / total)
    return "■" * used + "□" * (10 - used) + f"  {readable(free)} free of {readable(total)}"


def readable(size):
    for unit in ("bytes", "KB", "MB", "GB", "TB"):
        if size < 1000 or unit == "TB":
            return f"{size:.0f} {unit}" if unit == "bytes" else f"{size:.1f} {unit}"
        size /= 1000
    return ""


# The space a folder's files take, the folders inside counted once, links not followed.
def measure(path):
    total = 0
    pending = [path]
    while pending:
        folder = pending.pop()
        try:
            with os.scandir(folder) as entries:
                for entry in entries:
                    try:
                        if entry.is_dir(follow_symlinks=False):
                            pending.append(entry.path)
                        elif entry.is_file(follow_symlinks=False):
                            total += entry.stat(follow_symlinks=False).st_size
                    except OSError:
                        pass
        except OSError:
            pass
    return total


class FolderSizes(GObject.GObject, Nautilus.ColumnProvider, Nautilus.InfoProvider):
    def get_columns(self):
        return [Nautilus.Column(name="graphite_size", attribute="graphite_size", label="Size", description="Size, folders included")]

    def update_file_info_full(self, provider, handle, closure, file):
        if file.get_uri_scheme() != "file":
            return Nautilus.OperationResult.COMPLETE
        path = file.get_location().get_path()
        # A drive: the space left on it (measuring all of it would take too long).
        if os.path.ismount(os.path.realpath(path)):
            space = drive_space(path)
            if space:
                file.add_string_attribute("graphite_size", space)
            return Nautilus.OperationResult.COMPLETE
        try:
            stat = os.stat(path, follow_symlinks=False)
        except OSError:
            return Nautilus.OperationResult.COMPLETE
        if not file.is_directory():
            file.add_string_attribute("graphite_size", readable(stat.st_size))
            return Nautilus.OperationResult.COMPLETE

        with lock:
            known = answers.get(path)
            if known and known[1] == stat.st_mtime and time.monotonic() - known[0] < KEPT_FOR:
                file.add_string_attribute("graphite_size", readable(known[2]))
                return Nautilus.OperationResult.COMPLETE
            file.add_string_attribute("graphite_size", "Calculating...")
            if path in measured:
                return Nautilus.OperationResult.COMPLETE
            measured.add(path)

        def work():
            with measuring:
                size = measure(path)
            with lock:
                answers[path] = (time.monotonic(), stat.st_mtime, size)
                measured.discard(path)
            GLib.idle_add(ask_again)

        def ask_again():
            file.invalidate_extension_info()
            return False

        threading.Thread(target=work, daemon=True).start()
        return Nautilus.OperationResult.COMPLETE
