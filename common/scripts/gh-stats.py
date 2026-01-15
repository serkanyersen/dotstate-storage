#!/usr/bin/env python3
import os
import re
import sys
import json
import urllib.request
from datetime import datetime
from collections import defaultdict
from rich.console import Console
from rich.table import Table
from rich.text import Text

console = Console()

# ---- helpers: GitHub API ----

def gh_get(url: str, token: str | None):
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "gh-release-tables",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as resp:
        data = resp.read().decode("utf-8")
        return json.loads(data), resp.headers

def parse_next_link(link_header: str | None):
    if not link_header:
        return None
    # Link: <url>; rel="next", <url>; rel="last"
    for part in (p.strip() for p in link_header.split(",")):
        if 'rel="next"' in part:
            start = part.find("<") + 1
            end = part.find(">")
            return part[start:end]
    return None

def fmt_date(iso: str | None) -> str:
    if not iso:
        return ""
    try:
        dt = datetime.strptime(iso, "%Y-%m-%dT%H:%M:%SZ")
        return dt.strftime("%Y-%m-%d")
    except Exception:
        return iso

# ---- helpers: asset normalization ----

CHECKSUM_EXT_RE = re.compile(r"\.(sha256|sha512|sha1|md5|sig|asc)$", re.IGNORECASE)

def is_checksum_like(name: str) -> bool:
    return bool(CHECKSUM_EXT_RE.search(name))

def detect_platform(asset_name: str) -> str:
    """
    Convert asset filename to a short, consistent platform label.
    You can tweak these rules to match your naming scheme.
    """
    s = asset_name.lower()

    # OS
    if any(k in s for k in ["windows", "win32", "win64", "msvc", ".exe", ".msi"]):
        os_label = "windows"
    elif any(k in s for k in ["darwin", "macos", "osx", "apple"]):
        os_label = "macos"
    elif "linux" in s:
        os_label = "linux"
    elif any(k in s for k in ["freebsd", "openbsd", "netbsd"]):
        os_label = "bsd"
    else:
        os_label = "other"

    # Arch
    if any(k in s for k in ["aarch64", "arm64"]):
        arch = "arm64"
    elif any(k in s for k in ["x86_64", "amd64", "x64"]):
        arch = "x86_64"
    elif any(k in s for k in ["armv7", "armhf"]):
        arch = "armv7"
    elif any(k in s for k in ["i386", "x86", "386"]):
        arch = "x86"
    else:
        arch = "unknown"

    return f"{os_label}/{arch}"

def detect_packaging(asset_name: str) -> str:
    s = asset_name.lower()
    # Keep it minimal; just enough to distinguish if multiple exist per platform
    if s.endswith(".zip"):
        return "zip"
    if s.endswith(".tar.gz") or s.endswith(".tgz"):
        return "tar.gz"
    if s.endswith(".tar.xz"):
        return "tar.xz"
    if s.endswith(".exe"):
        return "exe"
    if s.endswith(".msi"):
        return "msi"
    if s.endswith(".dmg"):
        return "dmg"
    return "file"

def human_mb(num_bytes: int) -> str:
    return f"{num_bytes / (1024 * 1024):.2f}"

# ---- rendering ----

def print_release_table_rich(tag: str, name: str, published_at: str, rows: list[dict], version_total: int):
    title = f"{tag}"
    if name:
        title += f" — {name}"
    if published_at:
        title += f" ({published_at})"

    console.print()
    console.print(Text(title, style="bold"))
    console.print(f"Total downloads (all assets): {version_total}\n")

    table = Table(show_header=True, header_style="bold")

    table.add_column("Platform", no_wrap=True)
    table.add_column("Pkg", justify="right", no_wrap=True)
    table.add_column("Downloads", justify="right")
    table.add_column("Size (MB)", justify="right")
    table.add_column("Asset", overflow="fold")

    #table = Table(show_header=True, header_style="bold", show_lines=False)
    #table.add_column("Platform", no_wrap confirming=False)
    #table.add_column("Pkg", justify="right")
    #table.add_column("Downloads", justify="right")
    #table.add_column("Size (MB)", justify="right")
    #table.add_column("Asset (short)", overflow="fold")  # wraps nicely

    for r in sorted(rows, key=lambda x: (-x["downloads"], x["platform"], x["package"])):
        table.add_row(
            r["platform"],
            r["package"],
            str(r["downloads"]),
            r["size_mb"],
            r["short_name"],
        )

    console.print(table)


def print_release_table(tag: str, name: str, published_at: str, rows: list[dict], version_total: int):
    title = f"{tag}"
    if name:
        title += f" — {name}"
    if published_at:
        title += f" ({fmt_date(published_at)})"

    print()
    print(f"## {title}")
    print()
    print(f"**Total downloads (all assets): {version_total}**")
    print()
    print("| Platform | Package | Downloads | Size (MB) | Asset (short) |")
    print("|---|---:|---:|---:|---|")

    for r in sorted(rows, key=lambda x: (-x["downloads"], x["platform"], x["package"])):
        short = r["short_name"]
        print(f"| {r['platform']} | {r['package']} | {r['downloads']} | {r['size_mb']} | `{short}` |")

def shorten_asset_name(asset_name: str) -> str:
    # Reduce noise but keep some identity.
    # Example: "dotstate-x86_64-unknown-linux-gnu.tar.gz" -> "…linux…tar.gz"
    # If you prefer even shorter, just return packaging.
    s = asset_name
    # Strip leading project name prefix if present: keep from first dash onwards
    # (safe-ish; tweak for your naming)
    s2 = re.sub(r"^[^-]+-", "…", s)
    # If still long, compress triple-words
    if len(s2) > 50:
        s2 = s2[:47] + "…"
    return s2

def main():
    if len(sys.argv) < 2:
        print("Usage: gh_release_tables.py owner/repo [limit=20] [tag_prefix]")
        print("Env: GITHUB_TOKEN or GH_TOKEN recommended.")
        sys.exit(1)

    repo = sys.argv[1]
    limit = int(sys.argv[2]) if len(sys.argv) >= 3 else 20
    tag_prefix = sys.argv[3] if len(sys.argv) >= 4 else ""

    token = os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")

    url = f"https://api.github.com/repos/{repo}/releases?per_page=100&page=1"
    releases = []

    while url and len(releases) < limit * 3:  # buffer before filtering
        batch, headers = gh_get(url, token)
        releases.extend(batch)
        url = parse_next_link(headers.get("Link"))

    # Filter and take latest N
    if tag_prefix:
        releases = [r for r in releases if (r.get("tag_name") or "").startswith(tag_prefix)]
    releases = releases[:limit]

    # Print as Markdown (easy to read in terminal + paste into GitHub Issues/PRs)
    print(f"# GitHub Release Download Tables — {repo}")
    print()
    print(f"_Showing up to {len(releases)} release(s){' (filtered)' if tag_prefix else ''}._")
    print()

    for r in releases:
        tag = r.get("tag_name") or ""
        rel_name = r.get("name") or ""
        published_at = r.get("published_at") or ""
        assets = r.get("assets") or []

        # bucket: (platform, package) -> aggregated row
        buckets: dict[tuple[str, str], dict] = {}

        version_total = 0
        for a in assets:
            asset_name = a.get("name") or ""
            downloads = int(a.get("download_count") or 0)
            size = int(a.get("size") or 0)

            version_total += downloads

            # ignore checksum/signature files by default (they make the table noisy)
            if is_checksum_like(asset_name):
                continue

            platform = detect_platform(asset_name)
            package = detect_packaging(asset_name)
            key = (platform, package)

            if key not in buckets:
                buckets[key] = {
                    "platform": platform,
                    "package": package,
                    "downloads": 0,
                    "size_bytes": 0,
                    "short_name": shorten_asset_name(asset_name),
                }

            # sum downloads across same platform/package
            buckets[key]["downloads"] += downloads
            # keep max size (or sum; max is usually more meaningful here)
            buckets[key]["size_bytes"] = max(buckets[key]["size_bytes"], size)

        rows = []
        for b in buckets.values():
            rows.append({
                "platform": b["platform"],
                "package": b["package"],
                "downloads": b["downloads"],
                "size_mb": human_mb(b["size_bytes"]),
                "short_name": b["short_name"],
            })

        # print_release_table(tag, rel_name, published_at, rows, version_total)
        print_release_table_rich(tag, rel_name, fmt_date(published_at), rows, version_total)

if __name__ == "__main__":
    main()

