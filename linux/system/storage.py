#!/usr/bin/env python3
# Graphite's storage clean-up, for the Control Panel's Storage page (services/Storage.qml). It
# runs as the person. A scan measures the drives and what fills them; the caches and leftovers
# that can go, each with what deleting it costs; the screenshots and recordings since the last
# clean-up; old or big downloads; old Claude Code chats; and the Bin. The answer goes to
# ~/.local/state/graphite/storage.json. A clean takes what was chosen (JSON, on stdin): it
# deletes the caches and chats, puts the chosen files in the Bin and empties it when asked,
# printing a line per step ("STEP ...") and at the end the space that came back ("DONE bytes").
#
#   storage.py scan
#   storage.py clean   {"caches": [ids], "files": [paths], "chats": days, "system": bool,
#                       "bin": bool, "reviewed": bool} on stdin
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.join(HOME, ".local", "state")), "graphite")
CACHE = os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache"))
ANSWER = os.path.join(STATE, "storage.json")
HISTORY = os.path.join(STATE, "storage-history.json")
THUMBS = os.path.join(CACHE, "graphite", "thumbs")
ADMIN = "/usr/local/lib/graphite/graphite-admin"
DAY = 86400
CHAT_AGES = (7, 14, 30, 90)

# Folders in ~/.cache that stay: compiled shaders (their own choice below) and Graphite's own.
KEEP_CACHES = {"nvidia", "mesa_shader_cache", "mesa_shader_cache_db", "graphite", "dconf"}

# What has to stop before a cache can go, by process name.
BLOCKERS = {"claude-desktop": "Close Claude first", "Discord": "Close Discord first",
            "UnrealEditor": "Close Unreal Engine first", "EpicGamesLaunch": "Close the Epic Games Launcher first",
            "steam": "Close Steam first", "cargo": "Wait for the Rust build that's running", "Unity": "Close Unity first"}

# What the folders that fill a drive are, by their place in the home folder.
NAMES = {
    ".local/share/Trash": "Bin",
    ".local/share/Steam": "Steam",
    ".local/share/com.epicgames.eglv2": "Epic Games Launcher",
    ".local/share/com.epicgames.eglv2/FabLibrary": "Fab downloads",
    ".local/share/ModrinthApp": "Minecraft (Modrinth App)",
    ".local/share/flatpak": "Flathub apps",
    ".local/share/containers": "Ubuntu apps",
    ".var/app": "Flathub apps' files",
    ".config/Claude": "Claude app",
    ".config/Claude/vm_bundles": "Claude app's virtual machine",
    ".config/Epic": "Unreal Engine caches and settings",
    ".config/discord": "Discord",
    ".claude": "Claude Code",
    ".claude/projects": "Claude Code chats",
    ".cache": "Caches",
    ".cache/nvidia": "Compiled graphics shaders",
    ".cargo": "Rust packages",
    ".rustup": "Rust toolchains",
    ".nuget": ".NET packages",
    ".npm": "npm packages",
    "UnrealEngine": "Unreal Engine",
    "Unity": "Unity",
    "Unity/Hub/Editor": "Unity editors",
    "Applications": "Apps from websites",
    "Documents/Unreal Projects": "Unreal projects",
}
# Folders that are only containers: shown by what's inside (in the home folder; and by name on
# any drive, as a Steam library is, down to its games).
OPEN = {".local", ".local/share", ".config", ".var", ".var/app", "Documents", "Documents/Unreal Projects"}
OPEN_NAMES = {"SteamLibrary", "steamapps", "common", "Dev"}
STEAM_NAMES = {"shadercache": "Steam shader caches", "compatdata": "Steam games' Windows folders (saves, settings)",
               "downloading": "Steam downloads", "workshop": "Steam Workshop items"}


def run(command, timeout=60, stdin=subprocess.DEVNULL):
    try:
        done = subprocess.run(command, capture_output=True, text=True, timeout=timeout, stdin=stdin)
        return done.returncode, done.stdout, done.stderr
    except (OSError, subprocess.TimeoutExpired):
        return None, "", ""


def home(path):
    return os.path.join(HOME, path)


def user_dir(kind, fallback):
    code, out, _ = run(["xdg-user-dir", kind], timeout=5)
    path = out.strip() if code == 0 else ""
    return path if path and path != HOME else home(fallback)


def load(path):
    try:
        with open(path) as file:
            return json.load(file)
    except (OSError, ValueError):
        return {}


def save(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "w") as file:
        json.dump(value, file, indent=1)
    os.replace(path + ".tmp", path)


def say(line):
    print(line, flush=True)


# Bytes in all of these together (each counted once), staying on each one's own drive.
def size(paths, timeout=300):
    paths = [path for path in paths if os.path.lexists(path)]
    if not paths:
        return 0
    _, out, _ = run(["du", "-scxB1", "--"] + paths, timeout)
    lines = out.strip().splitlines()
    try:
        return int(lines[-1].split()[0]) if lines else 0
    except ValueError:
        return 0


def short(path):
    return "~" + path[len(HOME):] if path == HOME or path.startswith(HOME + "/") else path


# ---------- drives ----------

def drives():
    code, out, _ = run(["df", "-B1", "--output=target,size,used,avail,fstype"], timeout=20)
    found, devices = [], set()
    for line in out.splitlines()[1:]:
        parts = line.split()
        if len(parts) < 5 or not parts[1].isdigit():
            continue
        mount, total, used, free, kind = parts[0], int(parts[1]), int(parts[2]), int(parts[3]), parts[4]
        if mount != "/" and not mount.startswith(("/home", "/run/media/", "/media/", "/mnt/")):
            continue
        if kind not in ("ext4", "btrfs", "xfs", "f2fs", "exfat", "vfat", "ntfs", "ntfs3", "fuseblk"):
            continue
        try:
            device = os.stat(mount).st_dev
        except OSError:
            continue
        if device in devices:
            continue
        devices.add(device)
        label = "This computer" if mount == "/" else os.path.basename(mount)
        found.append({"mount": mount, "name": label, "size": total, "used": used, "free": free})
    return found


def free_space():
    total = 0
    for drive in drives():
        try:
            stat = os.statvfs(drive["mount"])
            total += stat.f_bavail * stat.f_frsize
        except OSError:
            pass
    return total


# Every folder's size down to `depth` levels, or None when it took too long.
def tree(root, depth, timeout):
    code, out, _ = run(["nice", "-n", "10", "ionice", "-c3", "du", "-x", "-B1", "-d", str(depth), "--", root], timeout)
    if code is None:
        return None
    sizes = {}
    for line in out.splitlines():
        parts = line.split("\t", 1)
        if len(parts) == 2 and parts[0].isdigit():
            sizes[parts[1]] = int(parts[0])
    return sizes if root in sizes else None


def name_of(path, base):
    relative = os.path.relpath(path, base) if base == HOME else None
    if relative in NAMES:
        return NAMES[relative]
    match = re.search(r"UnrealEngine/UE_([\d.]+)$", path)
    if match:
        return "Unreal Engine " + match.group(1)
    if re.search(r"/\.Trash(-\d+)?$", path):
        return "Bin"
    if os.path.basename(os.path.dirname(path)) == "steamapps" and os.path.basename(path) in STEAM_NAMES:
        return STEAM_NAMES[os.path.basename(path)]
    return os.path.basename(path)


# The folders that fill `root` most: containers (and any folder holding a quarter of it) are
# shown by what's inside, then the biggest ones, the rest together.
def breakdown(sizes, root, limit=14):
    children = {}
    for path in sizes:
        if path != root:
            children.setdefault(os.path.dirname(path), []).append(path)
    total = sizes[root]
    shown = [{"path": path, "size": sizes[path]} for path in children.get(root, [])]
    opened = True
    while opened:
        opened = False
        for entry in sorted(shown, key=lambda item: -item["size"]):
            path = entry.get("path")
            kids = children.get(path, []) if path else []
            relative = os.path.relpath(path, HOME) if path and root == HOME else None
            deep = path and os.path.relpath(path, root).count("/") >= 3
            if kids and not deep and (relative in OPEN or os.path.basename(path) in OPEN_NAMES or entry["size"] >= total / 4):
                shown.remove(entry)
                shown += [{"path": kid, "size": sizes[kid]} for kid in kids]
                rest = entry["size"] - sum(sizes[kid] for kid in kids)
                if rest > total / 100:
                    shown.append({"files": path, "size": rest})
                opened = True
                break
    shown.sort(key=lambda item: -item["size"])
    top = []
    for entry in shown[:limit]:
        if entry.get("path"):
            top.append({"name": name_of(entry["path"], root), "path": entry["path"], "where": short(entry["path"]), "size": entry["size"]})
        else:
            top.append({"name": "Other files in " + name_of(entry["files"], root), "path": entry["files"], "where": short(entry["files"]), "size": entry["size"]})
    rest = sum(entry["size"] for entry in shown[limit:])
    if rest > 0:
        top.append({"name": "Everything else", "path": "", "where": "", "size": rest})
    return top


# Code projects' build folders among the folders measured, outermost only: Rust's (a target
# folder beside Cargo.toml) and Unity's (a project's Library).
def build_folders(sizes, found):
    for path in sorted(sizes):
        if any(path.startswith(earlier + "/") for earlier in found["rust"] + found["unity"]):
            continue
        if is_build(path):
            found["rust" if os.path.basename(path) == "target" else "unity"].append(path)


def is_build(path):
    parent = os.path.dirname(path)
    if os.path.basename(path) == "target":
        return os.path.isfile(os.path.join(parent, "Cargo.toml"))
    if os.path.basename(path) == "Library":
        return os.path.isdir(os.path.join(parent, "ProjectSettings")) and os.path.isdir(os.path.join(parent, "Assets"))
    return False


def fill(drive, builds):
    root = drive["mount"]
    home_here = os.stat(HOME).st_dev == os.stat(root).st_dev
    sizes = tree(HOME if home_here else root, 7, 900)
    if sizes is None:
        drive["top"], drive["measured"] = [], False
        return
    build_folders(sizes, builds)
    base = HOME if home_here else root
    top = breakdown(sizes, base)
    if home_here and root != HOME:
        system = drive["used"] - sizes[HOME]
        if system > 0:
            top.append({"name": "Arch Linux and apps" if root == "/" else "Other folders", "path": "", "where": "Outside your home folder", "size": system})
            top.sort(key=lambda item: (item["name"] == "Everything else", -item["size"]))
    drive["top"], drive["measured"] = top, True


# ---------- what can go ----------

def running():
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/comm") as file:
                name = file.read().strip()
        except OSError:
            continue
        try:
            program = os.readlink(f"/proc/{entry}/exe")
        except OSError:
            program = ""
        found.append((name, program))
    return found


def version_key(path):
    return [int(part) if part.isdigit() else 0 for part in os.path.basename(path).split(".")]


def steam_libraries():
    libraries = [home(".local/share/Steam")]
    try:
        with open(home(".local/share/Steam/steamapps/libraryfolders.vdf")) as file:
            libraries += re.findall(r'"path"\s+"([^"]+)"', file.read())
    except OSError:
        pass
    return list(dict.fromkeys(libraries))


# Each cache and leftover that can be deleted: what it is, what deleting it costs, its folders,
# the app to close first (by process name), and whether it's chosen to begin with.
def cache_items(processes, builds):
    names = {name for name, _ in processes}
    programs = [program for _, program in processes if program]
    documents = user_dir("DOCUMENTS", "Documents")

    app_caches = [entry.path for entry in os.scandir(CACHE) if entry.name not in KEEP_CACHES] if os.path.isdir(CACHE) else []
    shaders = [home(".cache/nvidia")] + glob.glob(home(".cache/mesa_shader_cache*"))
    shaders += [os.path.join(library, "steamapps", "shadercache") for library in steam_libraries()]
    # The Claude app keeps the Claude Code it ran before each update; the newest one (and any
    # still running) stays.
    claude_versions = []
    for folder in (home(".config/Claude/claude-code"), home(".config/Claude/claude-code-vm")):
        versions = sorted((path for path in glob.glob(os.path.join(folder, "*")) if os.path.isdir(path)), key=version_key)
        claude_versions += [path for path in versions[:-1] if not any(program.startswith(path + "/") for program in programs)]
    browser_caches = ("Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "GPUPersistentCache")
    unreal = glob.glob(home(".config/Epic/UnrealEngine/*/DerivedDataCache"))
    # Unreal's cache server keeps running a while after Unreal closes; its data stays till then.
    if "zenserver" not in names:
        unreal += glob.glob(home(".config/Epic/UnrealEngine/Common/Zen/Data")) + glob.glob(home(".config/Epic/UnrealEngine/*/Saved/Zen"))
    for project in glob.glob(os.path.join(documents, "Unreal Projects", "*", "*.uproject")):
        unreal += [os.path.join(os.path.dirname(project), "DerivedDataCache"), os.path.join(os.path.dirname(project), "Intermediate")]

    items = [
        ("app-caches", "App caches", "Files apps keep to open faster. They make them again when needed.", app_caches, None, True),
        ("shaders", "Compiled graphics shaders", "Games compile them again, so each one's next start is slower.", shaders, "steam", False),
        ("claude-versions", "Old versions of Claude Code", "Copies the Claude app keeps from before its updates.", claude_versions, None, True),
        ("claude-cache", "Claude app caches", "Pages and pictures the Claude app keeps to open faster. Your chats stay.", [home(".config/Claude/" + name) for name in browser_caches], "claude-desktop", True),
        ("discord-cache", "Discord caches", "Pictures and videos Discord keeps from chats. It downloads them again.", [home(".config/discord/" + name) for name in browser_caches], "Discord", True),
        ("unreal", "Unreal Engine caches", "Unreal builds them again when a project opens, which takes a while.", unreal, "UnrealEditor", False),
        ("fab", "Fab downloads", "Assets the Epic Games Launcher downloaded. The ones added to a project stay in it.", [home(".local/share/com.epicgames.eglv2/FabLibrary")], "EpicGamesLaunch", False),
        ("rust-builds", "Rust build folders", "What cargo built from your code (each project's target folder). The next build starts from scratch.", builds.get("rust", []), "cargo", False),
        ("unity-libraries", "Unity project caches", "Each Unity project's Library folder. Unity imports the project again when it next opens, which takes a while.", builds.get("unity", []), "Unity", False),
    ]
    found = []
    for id, title, detail, paths, app, chosen in items:
        paths = [path for path in paths if os.path.lexists(path)]
        bytes = size(paths, timeout=900)
        if bytes < 1_000_000:
            continue
        blocked = BLOCKERS[app] if app and app in names else ""
        found.append({"id": id, "title": title, "detail": detail, "size": bytes, "default": chosen, "blocked": blocked,
                      "where": [short(path) for path in paths][:12], "paths": paths})
    return found


def to_bytes(number, unit):
    return int(float(number) * {"B": 1, "KiB": 1024, "MiB": 1024 ** 2, "GiB": 1024 ** 3, "TiB": 1024 ** 4}.get(unit, 1))


# Old package downloads (all but the newest of each, none of what's uninstalled) and the system
# log beyond 200 MB, as graphite-admin clean deletes them.
def system_leftovers():
    saved = 0
    for keep in (["-dk1"], ["-duk0"]):
        _, out, _ = run(["paccache"] + keep, timeout=60)
        match = re.search(r"disk space saved: ([\d.]+) (\w+)", out)
        if match:
            saved += to_bytes(match.group(1), match.group(2))
    return saved + max(0, size(["/var/log/journal"]) - 200 * 1024 ** 2)


def thumb(path, mtime):
    os.makedirs(THUMBS, exist_ok=True)
    out = os.path.join(THUMBS, hashlib.sha1(f"{path}:{mtime}".encode()).hexdigest() + ".jpg")
    if not os.path.exists(out):
        for start in (["-ss", "0.5"], []):
            run(["ffmpeg", "-loglevel", "error", "-y"] + start + ["-i", path, "-frames:v", "1", "-vf", "scale=360:-2", out], timeout=30)
            if os.path.exists(out):
                break
    return out if os.path.exists(out) else ""


def shot_folders():
    return [(os.path.join(user_dir("PICTURES", "Pictures"), "Screenshots"), False, (".png", ".jpg", ".jpeg", ".webp")),
            (os.path.join(user_dir("VIDEOS", "Videos"), "Screen Recordings"), True, (".mp4", ".mkv", ".webm"))]


# The screenshots and recordings since the last clean-up looked at them (the last 30 days the
# first time), newest first, and how many there are in all.
def shots(history):
    since = history.get("reviewedUntil") or time.time() - 30 * DAY
    found, count, total = [], 0, 0
    for folder, video, endings in shot_folders():
        if not os.path.isdir(folder):
            continue
        for entry in os.scandir(folder):
            if not entry.is_file(follow_symlinks=False) or not entry.name.lower().endswith(endings):
                continue
            stat = entry.stat(follow_symlinks=False)
            count += 1
            total += stat.st_size
            if stat.st_mtime > since:
                found.append({"path": entry.path, "name": entry.name, "size": stat.st_size, "time": int(stat.st_mtime), "video": video})
    found.sort(key=lambda item: -item["time"])
    found = found[:120]
    for item in found:
        item["thumb"] = thumb(item["path"], item["time"]) if item["video"] else item["path"]
    return found, {"count": count, "size": total}


# Downloads not touched in a month, or bigger than a gigabyte, biggest first.
def downloads():
    folder = user_dir("DOWNLOAD", "Downloads")
    now = time.time()
    found = []
    if not os.path.isdir(folder):
        return found
    for entry in os.scandir(folder):
        if entry.name.startswith("."):
            continue
        stat = entry.stat(follow_symlinks=False)
        if entry.name.endswith((".part", ".crdownload")) and now - stat.st_mtime < 3600:
            continue
        is_folder = entry.is_dir(follow_symlinks=False)
        bytes = size([entry.path]) if is_folder else stat.st_size
        if now - stat.st_mtime >= 30 * DAY or bytes >= 1_000_000_000:
            found.append({"path": entry.path, "name": entry.name, "size": bytes, "time": int(stat.st_mtime), "folder": is_folder})
    found.sort(key=lambda item: -item["size"])
    return found[:50]


# Claude Code's chats: one file each (and a folder of its tools' output, and the earlier copies
# of the files it changed). The one being written, and any from the last day, never go.
def chat_sessions():
    sessions = []
    for record in glob.glob(home(".claude/projects/*/*.jsonl")):
        name = os.path.basename(record)[:-6]
        if not re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", name):
            continue
        paths = [record] + [path for path in (record[:-6], home(".claude/file-history/" + name)) if os.path.isdir(path)]
        try:
            newest = max(os.stat(path).st_mtime for path in paths)
        except OSError:
            continue
        sessions.append({"paths": paths, "time": newest})
    return sessions


def chats():
    now = time.time()
    sessions = chat_sessions()
    paths = [path for session in sessions for path in session["paths"]]
    sizes = {}
    for start in range(0, len(paths), 500):
        _, out, _ = run(["du", "-sB1", "--"] + paths[start:start + 500], timeout=120)
        for line in out.splitlines():
            parts = line.split("\t", 1)
            if len(parts) == 2 and parts[0].isdigit():
                sizes[parts[1]] = int(parts[0])
    for session in sessions:
        session["size"] = sum(sizes.get(path, 0) for path in session["paths"])
    ages = {}
    for days in CHAT_AGES:
        old = [session for session in sessions if now - session["time"] > max(days, 1) * DAY]
        ages[str(days)] = {"count": len(old), "size": sum(session["size"] for session in old)}
    return {"count": len(sessions), "size": sum(session["size"] for session in sessions), "ages": ages}


def bins(found_drives):
    uid = os.getuid()
    places = [home(".local/share/Trash")]
    for drive in found_drives:
        places += [os.path.join(drive["mount"], f".Trash-{uid}"), os.path.join(drive["mount"], ".Trash", str(uid))]
    return size([place for place in places if os.path.isdir(place)])


def scan():
    history = load(HISTORY)
    found_drives = drives()
    builds = {"rust": [], "unity": []}
    for drive in found_drives:
        fill(drive, builds)
    items = cache_items(running(), builds)
    for item in items:
        del item["paths"]
    found_shots, all_shots = shots(history)
    save(ANSWER, {
        "time": int(time.time()),
        "drives": found_drives,
        "caches": items,
        "builds": builds,
        "system": system_leftovers(),
        "shots": found_shots,
        "allShots": all_shots,
        "downloads": downloads(),
        "chats": chats(),
        "bin": bins(found_drives),
        "lastCleaned": history.get("lastCleaned", 0),
        "lastFreed": history.get("lastFreed", 0),
    })


# ---------- cleaning ----------

def remove(path):
    # Only what the scan names: inside the home folder, a Steam library's shader cache, or a
    # code project's build folder.
    real = os.path.realpath(os.path.dirname(path))
    if not (real == HOME or real.startswith(HOME + "/") or path.rstrip("/").endswith("/steamapps/shadercache") or is_build(path)):
        return
    if os.path.islink(path) or os.path.isfile(path):
        os.remove(path)
    elif os.path.isdir(path):
        shutil.rmtree(path, ignore_errors=True)


def clean():
    request = json.load(sys.stdin)
    last = load(ANSWER)
    before = free_space()

    chosen = set(request.get("caches") or [])
    # The build folders the last scan found, if they still are.
    builds = {kind: [path for path in (last.get("builds") or {}).get(kind, []) if is_build(path)] for kind in ("rust", "unity")}
    for item in cache_items(running(), builds):
        if item["id"] in chosen and not item["blocked"]:
            say("STEP Deleting " + item["title"])
            for path in item["paths"]:
                try:
                    remove(path)
                except OSError:
                    pass

    days = int(request.get("chats") or 0)
    if days in CHAT_AGES:
        say("STEP Deleting old Claude Code chats")
        now = time.time()
        for session in chat_sessions():
            if now - session["time"] > days * DAY:
                for path in session["paths"]:
                    try:
                        remove(path)
                    except OSError:
                        pass

    # Files only from what the last scan listed (screenshots, recordings, downloads).
    listed = {item["path"] for item in last.get("shots", []) + last.get("downloads", [])}
    files = [path for path in request.get("files") or [] if path in listed and os.path.lexists(path)]
    if files:
        say("STEP Putting files in the Bin")
        run(["gio", "trash", "--"] + files, timeout=600)

    if request.get("system"):
        say("STEP Deleting old updates and logs")
        run(["pkexec", ADMIN, "clean"], timeout=900)
        run(["flatpak", "uninstall", "--user", "--unused", "-y", "--noninteractive"], timeout=600)

    if request.get("bin"):
        say("STEP Emptying the Bin")
        run(["gio", "trash", "--empty"], timeout=900)

    freed = max(0, free_space() - before)
    history = load(HISTORY)
    history["lastCleaned"] = int(time.time())
    history["lastFreed"] = freed
    if request.get("reviewed"):
        history["reviewedUntil"] = int(time.time())
    save(HISTORY, history)
    say(f"DONE {freed}")


if len(sys.argv) > 1 and sys.argv[1] == "clean":
    clean()
else:
    scan()
