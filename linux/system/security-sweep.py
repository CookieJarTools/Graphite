#!/usr/bin/env python3
# Graphite's security sweep, for the Control Panel's Privacy & security page
# (services/Security.qml), which runs it every day or week and shows what it found. It runs as
# the person and changes nothing: each check says in plain words what it found, with the
# details, its state ("ok"; "look", worth a look; "act", needs doing; "note", for knowing), and
# the fix the page can offer. The answer goes to ~/.local/state/graphite/security.json.
#
#   security-sweep.py [--malware]     --malware: also scan downloads and apps with ClamAV
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.join(HOME, ".local", "state")), "graphite")
CLAMAV = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")), "graphite", "clamav")


def run(command, timeout=60):
    try:
        done = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        return done.returncode, done.stdout, done.stderr
    except (OSError, subprocess.TimeoutExpired):
        return None, "", ""


def check(id, title, state, summary, details=None, fix=None):
    return {"id": id, "title": title, "state": state, "summary": summary, "details": details or [], "fix": fix}


# Installed packages with known security holes (Arch's security team's list, through arch-audit).
def holes():
    title = "Known security holes"
    if not shutil.which("arch-audit"):
        return check("holes", title, "note", "The checker isn't installed yet.", fix={"action": "install", "package": "arch-audit", "label": "Install it"})
    code, out, _ = run(["arch-audit", "--format", "%n\t%s\t%v\t%t"], timeout=90)
    if code is None or (code != 0 and not out):
        return check("holes", title, "note", "Couldn't reach Arch's list of security holes. It's tried again next time.")
    fixable, waiting = [], []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        name, severity, fixed, kind = parts[:4]
        text = f"{name}: {kind or 'a security hole'} ({severity.lower() or 'unknown risk'})"
        (fixable if fixed.strip() else waiting).append(text + (f", fixed in {fixed}" if fixed.strip() else ", no fix yet"))
    if fixable:
        serious = any(re.search(r"\((high|critical)", item) for item in fixable)
        return check("holes", title, "act" if serious else "look",
                     f"{len(fixable)} installed {'package has' if len(fixable) == 1 else 'packages have'} a known hole that an update fixes.",
                     fixable + waiting, {"action": "updates", "label": "Install updates"})
    if waiting:
        return check("holes", title, "note", f"{len(waiting)} known {'hole has' if len(waiting) == 1 else 'holes have'} no fix yet. Updates bring the fixes as they come.", waiting)
    return check("holes", title, "ok", "None of your installed packages has a known security hole.")


def firewall():
    on = False
    try:
        on = "ENABLED=yes" in open("/etc/ufw/ufw.conf").read()
    except OSError:
        pass
    active = run(["systemctl", "is-active", "ufw"])[1].strip() == "active"
    if on and active:
        return check("firewall", "Firewall", "ok", "On. Connections from the network are blocked unless you started them.")
    return check("firewall", "Firewall", "act", "Off. Anything on the network can try to reach this computer.", fix={"action": "firewall", "label": "Turn it on"})


# What listens for connections from the network (not just from this computer).
KNOWN_PORTS = {22: "remote sign-in (SSH)", 631: "printing", 1900: "finding devices on the network (UPnP)",
               5353: "finding devices on the network (mDNS)", 27036: "Steam (streaming games to other devices)",
               27031: "Steam (streaming)", 57621: "Spotify (playing on other devices)", 3389: "remote desktop",
               5900: "screen sharing (VNC)", 445: "file sharing (Samba)", 139: "file sharing (Samba)"}


def listening(firewall_on):
    title = "Open to the network"
    _, out, _ = run(["ss", "-Htuln"])
    found = {}
    for line in out.splitlines():
        fields = line.split()
        if len(fields) < 5:
            continue
        address = fields[4]
        host, _, port = address.rpartition(":")
        host = host.strip("[]").split("%")[0]
        if host.startswith("127.") or host in ("::1", "localhost") or host.startswith("224.") or host.startswith("ff"):
            continue
        try:
            port = int(port)
        except ValueError:
            continue
        # Apps' own passing UDP ports (calls, game traffic) aren't services: only known ones count.
        if fields[0] == "udp" and port not in KNOWN_PORTS and port >= 32768:
            continue
        found[port] = KNOWN_PORTS.get(port, f"something on port {port} ({fields[0]})")
    if not found:
        return check("ports", title, "ok", "Nothing on this computer waits for connections from the network.")
    details = [found[port] for port in sorted(found)]
    if firewall_on:
        return check("ports", title, "note", f"{len(found)} {'thing waits' if len(found) == 1 else 'things wait'} for connections, and the firewall keeps the network from reaching them.", details)
    return check("ports", title, "look", f"{len(found)} {'thing waits' if len(found) == 1 else 'things wait'} for connections from the network, with the firewall off.", details, {"action": "firewall", "label": "Turn the firewall on"})


def remote_signin():
    active = run(["systemctl", "is-active", "sshd"])[1].strip() == "active"
    if not active:
        return check("ssh", "Remote sign-in", "ok", "Off. Nobody can sign in to this computer over the network.")
    passwords = True
    try:
        config = open("/etc/ssh/sshd_config").read()
        passwords = not re.search(r"^\s*PasswordAuthentication\s+no", config, re.M)
    except OSError:
        pass
    return check("ssh", "Remote sign-in", "look", "On (SSH)" + (", and it accepts passwords: a strong password matters." if passwords else ", with keys only."))


# Wrong passwords or PINs in the last week: at sign-in, unlocking, and administrator prompts.
def signins():
    title = "Sign-in attempts"
    _, out, _ = run(["journalctl", "--since", "-7 days", "--no-pager", "-q", "-o", "cat", "-g", "authentication failure|FAILED LOGIN|faillock"], timeout=60)
    failures = [line for line in out.splitlines() if "authentication failure" in line or "FAILED LOGIN" in line]
    locks = [line for line in out.splitlines() if "faillock" in line and ("lock" in line.lower())]
    where = {}
    for line in failures:
        service = re.search(r"pam_unix\(([^:)]+)", line)
        name = {"polkit-1": "administrator prompts", "greetd": "the sign-in screen", "graphite-lock": "the lock screen",
                "sudo": "the terminal (sudo)", "login": "a text sign-in"}.get(service.group(1) if service else "", "elsewhere")
        where[name] = where.get(name, 0) + 1
    details = [f"{count} at {name}" for name, count in sorted(where.items(), key=lambda item: -item[1])]
    if not failures:
        return check("signins", title, "ok", "No wrong passwords or PINs in the last week.")
    if len(failures) > 20 or locks:
        return check("signins", title, "look", f"{len(failures)} wrong passwords or PINs in the last week{', and the account was paused' if locks else ''}. If that wasn't you, change your password.", details, {"action": "accounts", "label": "Accounts"})
    return check("signins", title, "note", f"{len(failures)} wrong {'password or PIN' if len(failures) == 1 else 'passwords or PINs'} in the last week.", details)


# What starts by itself: apps at sign-in, and services set up in the home folder, where
# unwanted software hides to come back.
def startup():
    title = "Starts by itself"
    apps, services = [], []
    for entry in sorted(glob.glob(os.path.join(HOME, ".config", "autostart", "*.desktop"))):
        text = open(entry, errors="replace").read()
        if re.search(r"^Hidden=true", text, re.M | re.I):
            continue
        name = re.search(r"^Name=(.*)$", text, re.M)
        apps.append(name.group(1) if name else os.path.basename(entry))
    for wanted in sorted(glob.glob(os.path.join(HOME, ".config", "systemd", "user", "*.wants", "*"))):
        unit = os.path.realpath(wanted)
        if unit.startswith(os.path.join(HOME, "")):
            services.append(os.path.basename(wanted) + " (set up in your home folder)")
    details = [f"{app} (when you sign in)" for app in apps] + services
    if services:
        return check("startup", title, "look", f"{len(services)} background {'service was' if len(services) == 1 else 'services were'} set up in your home folder. Check you know {'it' if len(services) == 1 else 'them'}.", details)
    if apps:
        return check("startup", title, "note", f"{len(apps)} {'app opens' if len(apps) == 1 else 'apps open'} when you sign in.", details, {"action": "startup", "label": "Startup apps"})
    return check("startup", title, "ok", "Nothing extra starts by itself.")


# Flathub apps that may read every file in the home folder (or the whole computer).
def flatpak_access():
    title = "Apps that can see all your files"
    if not shutil.which("flatpak"):
        return None
    _, out, _ = run(["flatpak", "list", "--app", "--columns=application,name"])
    wide = []
    for line in out.splitlines():
        parts = line.split("\t")
        app, name = parts[0], parts[1] if len(parts) > 1 else parts[0]
        _, permissions, _ = run(["flatpak", "info", "--show-permissions", app])
        match = re.search(r"^filesystems=(.*)$", permissions, re.M)
        places = match.group(1).split(";") if match else []
        if any(place.split(":")[0] in ("host", "home", "host-os") for place in places):
            wide.append(name)
    if not wide:
        return check("files", title, "ok", "No Flathub app can read all your files.")
    return check("files", title, "note", f"{len(wide)} Flathub {'app' if len(wide) == 1 else 'apps'} can read every file in your home folder. That's usual for browsers and editors; for anything else, check you trust it.", wide)


def update_age():
    title = "Updates"
    newest = None
    try:
        for line in open("/var/log/pacman.log", errors="replace"):
            if "starting full system upgrade" in line:
                newest = line[1:26]
    except OSError:
        pass
    if not newest:
        return check("age", title, "note", "Couldn't tell when the system was last updated.")
    try:
        when = time.mktime(time.strptime(newest[:19], "%Y-%m-%dT%H:%M:%S"))
    except ValueError:
        return None
    days = int((time.time() - when) / 86400)
    if days > 45:
        return check("age", title, "act", f"The system was last updated {days} days ago. Fixes for security holes come with updates.", fix={"action": "updates", "label": "Install updates"})
    if days > 14:
        return check("age", title, "look", f"The system was last updated {days} days ago.", fix={"action": "updates", "label": "Install updates"})
    return check("age", title, "ok", "Up to date: last updated " + ("today." if days == 0 else "yesterday." if days == 1 else f"{days} days ago."))


def secure_boot():
    try:
        value = open("/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c", "rb").read()
        on = len(value) >= 5 and value[4] == 1
    except OSError:
        return None
    if on:
        return check("secureboot", "Secure Boot", "ok", "On. The computer only starts software that's signed.")
    return check("secureboot", "Secure Boot", "note", "Off. It stops tampered start-up software, but on Linux it needs setting up in the PC's firmware and signing your own start-up files.")


# Downloads, apps installed outside Arch and Flathub, and the desktop, through ClamAV with its
# signatures kept in the person's own cache (fetched first).
def malware():
    title = "Malware in downloads and apps"
    if not shutil.which("clamscan"):
        return check("malware", title, "note", "The scanner (ClamAV) isn't installed yet.", fix={"action": "install", "package": "clamav", "label": "Install it"})
    os.makedirs(CLAMAV, exist_ok=True)
    config = os.path.join(CLAMAV, "freshclam.conf")
    with open(config, "w") as file:
        file.write(f"DatabaseDirectory {CLAMAV}\nDatabaseMirror database.clamav.net\n")
    run(["freshclam", f"--config-file={config}", f"--datadir={CLAMAV}", "--quiet"], timeout=900)
    if not glob.glob(os.path.join(CLAMAV, "*.c[lv]d")):
        return check("malware", title, "note", "Couldn't download the scanner's list of malware. It's tried again next time.")
    places = [place for place in (os.path.join(HOME, name) for name in ("Downloads", "Applications", "Desktop", ".local/bin")) if os.path.isdir(place)]
    code, out, _ = run(["nice", "-n", "19", "ionice", "-c", "3", "clamscan", f"--database={CLAMAV}", "--recursive", "--infected", "--no-summary"] + places, timeout=3600)
    infected = [line.rsplit(" FOUND", 1)[0] for line in out.splitlines() if line.endswith(" FOUND")]
    if infected:
        return check("malware", title, "act", f"{len(infected)} {'file looks' if len(infected) == 1 else 'files look'} like malware. Move {'it' if len(infected) == 1 else 'them'} to the Wastebasket unless you're sure.",
                     infected, {"action": "trash", "label": "Move to Wastebasket", "files": [line.split(": ", 1)[0] for line in infected]})
    if code is None:
        return check("malware", title, "note", "The scan didn't finish. It's tried again next time.")
    return check("malware", title, "ok", "Nothing found in " + ", ".join(os.path.basename(place) for place in places) + ".")


def main():
    with_malware = "--malware" in sys.argv
    wall = firewall()
    checks = [holes(), wall, listening(wall["state"] == "ok"), remote_signin(), signins(), startup(), flatpak_access(), update_age(), secure_boot()]
    if with_malware:
        checks.append(malware())
    checks = [found for found in checks if found]
    os.makedirs(STATE, exist_ok=True)
    answer = os.path.join(STATE, "security.json")
    with open(answer + ".tmp", "w") as file:
        json.dump({"time": int(time.time()), "malware": with_malware, "checks": checks}, file, indent=1)
    os.replace(answer + ".tmp", answer)


main()
