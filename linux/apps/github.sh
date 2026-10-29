#!/usr/bin/env bash
# Apps from GitHub, for the Control Panel's Get apps (services/Desktop.qml): a project found by
# its link ("https://github.com/owner/repo", or "owner/repo") or by searching, and installed the
# best way this computer has. From Arch Linux or Flathub when the project is there (they update
# with the system); otherwise its newest release's download for 64-bit Linux, in this order: an
# AppImage, a Flatpak, an Arch package, a .tar.gz, .tar.xz or .zip of a Linux build, then a .deb,
# installed by install-app.sh. Source code alone, Windows and Mac files, checksums and signatures
# are never chosen. GitHub's answers are kept for ten minutes; with GitHub's own tool signed in
# (gh) its token is sent, for many more searches an hour.
#
#   github.sh find OWNER/REPO|LINK    the project and what would be installed, as JSON
#   github.sh search WORDS            up to six projects, the most starred first, as JSON
#   github.sh install OWNER/REPO|LINK installs it; what went wrong, in plain words, on stderr
set -uo pipefail
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/graphite/github"
mkdir -p "$cache"

say() { printf '%s\n' "$1" >&2; }

# The repository named by a link or "owner/repo", as "owner/repo"; nothing when it isn't one.
repo_of() {
    local text="${1#"${1%%[![:space:]]*}"}"
    text="${text%"${text##*[![:space:]]}"}"
    text="${text#http://}"; text="${text#https://}"; text="${text#www.}"; text="${text#github.com/}"
    if [[ "$text" =~ ^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)(/.*)?$ ]]; then
        local repo="${BASH_REMATCH[2]%.git}"
        [ -n "$repo" ] && printf '%s/%s\n' "${BASH_REMATCH[1]}" "$repo"
    fi
}

# GitHub's API, answers kept for ten minutes. The token travels in a header file only this
# person can read, never on a command line others could see.
api() {
    local path="$1" key file headers status
    key="$(printf '%s' "$path" | sha1sum | cut -c1-16)"
    file="$cache/$key.json"
    if [ -f "$file" ] && [ -n "$(find "$file" -mmin -10 2>/dev/null)" ]; then
        cat "$file"
        return 0
    fi
    headers="$(mktemp)"
    chmod 600 "$headers"
    printf 'Accept: application/vnd.github+json\nX-GitHub-Api-Version: 2022-11-28\n' > "$headers"
    if command -v gh >/dev/null && token="$(gh auth token 2>/dev/null)" && [ -n "$token" ]; then
        printf 'Authorization: Bearer %s\n' "$token" >> "$headers"
    fi
    status="$(curl -sS -L --max-time 20 -H @"$headers" -o "$file.part" -w '%{http_code}' "https://api.github.com/$path" 2>/dev/null)"
    rm -f "$headers"
    case "$status" in
        200) mv "$file.part" "$file"; cat "$file" ;;
        403 | 429) rm -f "$file.part"; say "GitHub is busy, try again in a minute."; return 2 ;;
        404) rm -f "$file.part"; return 4 ;;
        *) rm -f "$file.part"; say "GitHub couldn't be reached. Check your internet connection."; return 1 ;;
    esac
}

# The project, its newest release and the way to install it: { repo, owner, name, description,
# stars, url, homepage, release, released, choice: { kind: arch|flathub|download, ... } or null,
# reason, aur }.
find_repo() {
    local repo="$1" info release
    info="$(api "repos/$repo")"
    case $? in
        0) ;;
        4) say "There's no project at github.com/$repo."; return 1 ;;
        *) return 1 ;;
    esac
    # The newest release; a project with only pre-releases gives its newest one.
    release="$(api "repos/$repo/releases/latest")" || release="$(api "repos/$repo/releases?per_page=5" 2>/dev/null)" || release="null"
    # Through files: a release with many downloads is too long for the environment.
    local answers
    answers="$(mktemp -d)"
    printf '%s' "$info" > "$answers/info.json"
    printf '%s' "$release" > "$answers/release.json"
    ANSWERS="$answers" GITHUB_OWN_DOWNLOAD="${GITHUB_OWN_DOWNLOAD:-}" python3 -I - <<'PYTHON'
import gzip, json, os, re, subprocess, urllib.request

info = json.load(open(os.path.join(os.environ["ANSWERS"], "info.json")))
release = json.loads(open(os.path.join(os.environ["ANSWERS"], "release.json")).read() or "null")
if isinstance(release, list):
    release = next((r for r in release if not r.get("draft")), None)
owner, name = info["owner"]["login"], info["name"]
slug = f"{owner}/{name}".lower()
homepage = (info.get("homepage") or "").strip()

def same_site(a, b):
    clean = lambda url: re.sub(r"^(https?://)?(www\.)?", "", (url or "").strip().lower()).rstrip("/")
    return bool(a) and bool(b) and clean(a) == clean(b)

def from_github(url):
    return f"github.com/{slug}" in (url or "").lower()

# Arch Linux's own package, when its project page is this one or this project's website.
def arch():
    for candidate in dict.fromkeys([name.lower(), re.sub(r"[-_](desktop|app|releases)$", "", name.lower())]):
        try:
            out = subprocess.run(["pacman", "-Si", candidate], capture_output=True, text=True, timeout=10).stdout
        except Exception:
            continue
        url = re.search(r"^URL\s*:\s*(\S+)", out, re.M)
        repo_name = re.search(r"^Repository\s*:\s*(\S+)", out, re.M)
        if url and repo_name and repo_name.group(1) in ("core", "extra", "multilib") and (from_github(url.group(1)) or same_site(url.group(1), homepage)):
            return candidate
    return None

# Flathub's app whose source or website is this project (from the catalogue Flatpak keeps).
def flathub():
    for path in (os.path.expanduser("~/.local/share/flatpak/appstream/flathub/x86_64/active/appstream.xml.gz"),
                 "/var/lib/flatpak/appstream/flathub/x86_64/active/appstream.xml.gz"):
        if not os.path.exists(path):
            continue
        text = gzip.open(path, "rt", encoding="utf-8", errors="replace").read()
        for match in re.finditer(r'github\.com/' + re.escape(slug) + r'(?:\.git)?/?<', text, re.I):
            start = text.rfind("<component", 0, match.start())
            found = re.search(r"<id>([^<]+)</id>", text[start:match.start()])
            if found:
                return found.group(1).removesuffix(".desktop")
        return None
    return None

# A download from the release that runs on 64-bit Linux, the best kind first.
def download():
    if not release:
        return None
    # Other machines and systems (as words of their own: "alarm" isn't ARM), and what isn't an app.
    other = re.compile(r"((?<![a-z])(arm(64|hf|v[5-8]|el)?|aarch64|i[3-6]86|x86[-_]?32|riscv\d*|ppc\w*|s390x?|mips\w*|loong\w*|win(dows|32|64)?|mac(os)?|darwin|osx|apple|universal|source|src)(?![a-z])|\.exe$|\.msi$|\.dmg$|\.pkg$|\.sha\d*|\.sig$|\.asc$|\.sum$|checksum|\.txt$|\.json$|\.ya?ml$|\.blockmap$|\.zsync$|\.sbom|\.pem$|\.crt$|\.apk$|\.snap$|\.rpm$)", re.I)
    ours = re.compile(r"(x86[-_]?64|amd64|x64|linux64)", re.I)
    # A .deb last: it goes into the Ubuntu container (made the first time), and a tool without an
    # app entry can't be opened from there; a Linux build archive runs here as it is.
    kinds = [("appimage", r"\.appimage$"), ("flatpak", r"\.flatpak$"), ("pkg", r"\.pkg\.tar\.(zst|xz)$"), ("archive", r"\.(tar\.gz|tgz|tar\.xz|tar\.bz2|zip)$"), ("deb", r"\.deb$")]
    assets = [a for a in release.get("assets", []) if not other.search(a["name"])]
    for kind, pattern in kinds:
        found = [a for a in assets if re.search(pattern, a["name"], re.I)]
        # A build archive has to say it's for Linux; the others are Linux-only already.
        if kind == "archive":
            found = [a for a in found if re.search(r"linux", a["name"], re.I)]
        if not found:
            continue
        found.sort(key=lambda a: (not ours.search(a["name"]), len(a["name"])))
        best = found[0]
        return {"kind": "download", "type": kind, "file": best["name"], "url": best["browser_download_url"], "size": best.get("size", 0)}
    return None

def aur():
    try:
        with urllib.request.urlopen(f"https://aur.archlinux.org/rpc/v5/search/{name.lower()}?by=name", timeout=8) as answer:
            for package in json.load(answer).get("results", []):
                if from_github(package.get("URL")) or same_site(package.get("URL"), homepage):
                    return package["Name"]
    except Exception:
        pass
    return None

choice, reason, in_aur = None, "", None
# GITHUB_OWN_DOWNLOAD=1: the project's own download even when Arch or Flathub has it (for checking).
package = None if os.environ.get("GITHUB_OWN_DOWNLOAD") else arch()
if package:
    choice = {"kind": "arch", "package": package}
else:
    app = None if os.environ.get("GITHUB_OWN_DOWNLOAD") else flathub()
    if app:
        choice = {"kind": "flathub", "app": app}
    else:
        choice = download()
if not choice:
    in_aur = aur()
    reason = "This project doesn't publish a ready-made Linux download."
    if in_aur:
        reason += f" It's in the AUR as {in_aur}, which builds it from its code."

print(json.dumps({
    "repo": f"{owner}/{name}", "owner": owner, "name": name,
    "description": info.get("description") or "", "stars": info.get("stargazers_count", 0),
    "url": info.get("html_url"), "homepage": homepage,
    "release": (release or {}).get("name") or (release or {}).get("tag_name") or "",
    "released": (release or {}).get("published_at") or "",
    "choice": choice, "reason": reason, "aur": in_aur
}))
PYTHON
    local code=$?
    rm -rf "$answers"
    return "$code"
}

search() {
    local words="$*" query
    query="$(python3 -I -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$words")"
    api "search/repositories?q=$query&sort=stars&order=desc&per_page=6" | python3 -I -c '
import json, sys
found = json.load(sys.stdin).get("items", [])
print(json.dumps([{"repo": r["full_name"], "owner": r["owner"]["login"], "name": r["name"],
    "description": r.get("description") or "", "stars": r.get("stargazers_count", 0), "url": r["html_url"]} for r in found]))'
}

install() {
    local repo="$1" found kind
    found="$(find_repo "$repo")" || exit 1
    kind="$(printf '%s' "$found" | python3 -I -c 'import json, sys; c = json.load(sys.stdin)["choice"]; print(c["kind"] if c else "")')"
    case "$kind" in
        arch)
            exec bash "$here/install-app.sh" --package "$(printf '%s' "$found" | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["choice"]["package"])')" ;;
        flathub)
            exec bash "$here/install-app.sh" --flathub "$(printf '%s' "$found" | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["choice"]["app"])')" ;;
        download) ;;
        *)
            say "$(printf '%s' "$found" | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["reason"])')"
            exit 1 ;;
    esac

    local url file name owner folder target
    url="$(printf '%s' "$found" | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["choice"]["url"])')"
    file="$(printf '%s' "$found" | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["choice"]["file"])')"
    name="$(printf '%s' "$found" | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["name"])')"
    owner="${repo%%/*}"
    # Into a folder of its own rather than Downloads, where a finished download offers to
    # install itself (Desktop.qml) and would ask a second time.
    folder="$cache/downloads"
    mkdir -p "$folder"
    target="$folder/$(basename "$file")"
    notify-send -a "Graphite Desk" -i system-software-install "Downloading $name..." "$file from $owner on GitHub" 2>/dev/null
    curl -sS -L --fail --max-time 1800 -o "$target" "$url" 2>/dev/null || { say "The download from GitHub didn't finish. Check your internet connection."; exit 1; }
    # A page in place of the file (GitHub down, a link gone): nothing to install.
    if [ ! -s "$target" ] || file -b --mime-type "$target" | grep -q -E '^text/(html|plain)$'; then
        rm -f "$target"
        say "GitHub sent a web page instead of $file. Try again later."
        exit 1
    fi
    # Its own name and the owner's picture, for the launcher, should the app not bring them.
    curl -sS -L --max-time 15 -o "$folder/$owner.png" "https://github.com/$owner.png?size=128" 2>/dev/null || true
    GRAPHITE_APP_NAME="$name" GRAPHITE_APP_ICON="$folder/$owner.png" bash "$here/install-app.sh" "$target"
    local code=$?
    rm -f "$target"
    [ "$code" = 0 ] || say "$file couldn't be installed."
    exit "$code"
}

case "${1:-}" in
    find)
        repo="$(repo_of "${2:-}")"
        [ -n "$repo" ] || { say "That isn't a GitHub project link."; exit 1; }
        find_repo "$repo" ;;
    search)
        shift
        [ $# -gt 0 ] || exit 1
        search "$@" ;;
    install)
        repo="$(repo_of "${2:-}")"
        [ -n "$repo" ] || { say "That isn't a GitHub project link."; exit 1; }
        install "$repo" ;;
    *)
        say "Usage: github.sh find|install OWNER/REPO, or github.sh search WORDS"
        exit 2 ;;
esac
