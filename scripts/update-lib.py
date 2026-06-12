#!/usr/bin/env python3
"""Version checks and state for Pisces SMP auto-updater."""

from __future__ import annotations

import hashlib
import json
import re
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

USER_AGENT = "piscessmp/1.0 (debian-updater)"
PAPER_VERSION = "1.21.11"
MC_VERSION = "1.21.11"


@dataclass
class UpdateItem:
    name: str
    path: Path
    current_build: str | None
    latest_build: str
    download_url: str
    output_name: str
    changed: bool


def sha256_file(path: Path) -> str | None:
    if not path.is_file():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fetch_json(url: str) -> Any:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def download_file(url: str, dest: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        data = response.read()
    if len(data) < 1024:
        raise RuntimeError(f"Download too small for {dest.name}")
    tmp = dest.with_suffix(dest.suffix + ".tmp")
    tmp.write_bytes(data)
    tmp.replace(dest)


def verify_jar(path: Path) -> None:
    import zipfile

    if not zipfile.is_zipfile(path):
        raise RuntimeError(f"{path.name} is not a valid jar")


def modrinth_latest(project: str, loader: str, game_version: str) -> tuple[str, str, str]:
    query = urllib.parse.urlencode(
        {
            "loaders": json.dumps([loader]),
            "game_versions": json.dumps([game_version]),
        }
    )
    versions = fetch_json(f"https://api.modrinth.com/v2/project/{project}/version?{query}")
    if not versions:
        raise RuntimeError(f"No Modrinth release for {project} ({loader}, {game_version})")
    latest = versions[0]
    primary = next(file for file in latest["files"] if file["primary"])
    return latest["version_number"], primary["url"], primary["filename"]


def paper_latest() -> tuple[str, str, str]:
    builds = fetch_json(
        f"https://fill.papermc.io/v3/projects/paper/versions/{PAPER_VERSION}/builds"
    )
    stable = [build for build in builds if build.get("channel") == "STABLE"]
    latest = (stable or builds)[-1]
    download = latest["downloads"]["server:default"]
    build_id = str(latest["id"])
    return build_id, download["url"], download["checksums"]["sha256"]


def hangar_latest(namespace: str, slug: str, platform: str = "PAPER") -> tuple[str, str, str]:
    query = urllib.parse.urlencode({"limit": 10, "offset": 0, "platform": platform})
    payload = fetch_json(
        f"https://hangar.papermc.io/api/v1/projects/{namespace}/{slug}/versions?{query}"
    )
    versions = payload.get("result") or []
    if not versions:
        raise RuntimeError(f"No Hangar release for {namespace}/{slug} ({platform})")
    latest = versions[0]
    platform_download = latest["downloads"][platform]
    return (
        latest["name"],
        platform_download["downloadUrl"],
        platform_download["fileInfo"]["name"],
    )


def github_release_asset(repo: str, asset_pattern: str) -> tuple[str, str]:
    release = fetch_json(f"https://api.github.com/repos/{repo}/releases/latest")
    tag = release["tag_name"]
    pattern = re.compile(asset_pattern)
    for asset in release.get("assets", []):
        if pattern.search(asset["name"]):
            return tag, asset["browser_download_url"]
    raise RuntimeError(f"No asset matching {asset_pattern!r} in {repo} {tag}")


def load_state(state_path: Path) -> dict[str, Any]:
    if not state_path.is_file():
        return {}
    return json.loads(state_path.read_text())


def save_state(state_path: Path, state: dict[str, Any]) -> None:
    state["last_check"] = datetime.now(timezone.utc).isoformat()
    state_path.write_text(json.dumps(state, indent=2) + "\n")


def build_plan(root: Path) -> list[UpdateItem]:
    server_dir = root / "server"
    plugins_dir = server_dir / "plugins"
    paper_path = server_dir / "paper.jar"
    state_path = server_dir / ".update-state.json"
    state = load_state(state_path)
    items: list[UpdateItem] = []

    paper_build, paper_url, paper_sha = paper_latest()
    current_paper = state.get("paper", {})
    current_paper_build = current_paper.get("build")
    current_paper_hash = sha256_file(paper_path)
    paper_changed = (
        current_paper_build != paper_build
        or current_paper_hash != paper_sha
        or not paper_path.is_file()
    )
    items.append(
        UpdateItem(
            name="Paper",
            path=paper_path,
            current_build=current_paper_build,
            latest_build=paper_build,
            download_url=paper_url,
            output_name="paper.jar",
            changed=paper_changed,
        )
    )

    plugin_specs: list[tuple[str, str, str, str]] = [
        ("Geyser-Spigot", "geyser", "latest", "Geyser-Spigot.jar"),
        ("Floodgate-Spigot", "floodgate", "latest", "Floodgate-Spigot.jar"),
        (
            "Simple Voice Chat",
            "modrinth:simple-voice-chat:bukkit",
            MC_VERSION,
            "voicechat-bukkit.jar",
        ),
        (
            "SimpleVoice-Geyser",
            "modrinth:simplevoice-geyser:paper",
            MC_VERSION,
            "SimpleVoice-Geyser.jar",
        ),
        ("Staff++", "modrinth:staff++:paper", MC_VERSION, "StaffPlusPlus.jar"),
        ("ViaVersion", "modrinth:viaversion:paper", MC_VERSION, "ViaVersion.jar"),
        ("ViaBackwards", "modrinth:viabackwards:paper", MC_VERSION, "ViaBackwards.jar"),
        ("LuckPerms", "modrinth:luckperms:bukkit", MC_VERSION, "LuckPerms.jar"),
        ("TAB", "github:NEZNAMY/TAB:Vanilla", MC_VERSION, "TAB.jar"),
        ("CoreProtect", "modrinth:coreprotect:paper", MC_VERSION, "CoreProtect.jar"),
        ("DiscordSRV", "modrinth:discordsrv:paper", MC_VERSION, "DiscordSRV.jar"),
        ("BlueMap", "modrinth:bluemap:paper", MC_VERSION, "BlueMap.jar"),
        ("PlaceholderAPI", "modrinth:placeholderapi:paper", MC_VERSION, "PlaceholderAPI.jar"),
        ("EssentialsX", "github:EssentialsX/Essentials:EssentialsX", MC_VERSION, "EssentialsX.jar"),
        ("BetterRTP", "hangar:Ronan:BetterRTP", MC_VERSION, "BetterRTP.jar"),
        ("WorldEdit", "modrinth:worldedit:paper", MC_VERSION, "WorldEdit.jar"),
        ("Multiverse-Core", "hangar:Multiverse:Multiverse-Core", MC_VERSION, "Multiverse-Core.jar"),
        ("VoidGen", "modrinth:voidgen:paper", MC_VERSION, "VoidGen.jar"),
    ]

    for name, source, version_key, output_name in plugin_specs:
        if source == "geyser":
            url = "https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot"
            latest_build = "latest"
        elif source == "floodgate":
            url = "https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot"
            latest_build = "latest"
        elif source.startswith("modrinth:"):
            _, project, loader = source.split(":")
            latest_build, url, _ = modrinth_latest(project, loader, version_key)
        elif source.startswith("hangar:"):
            _, namespace, slug = source.split(":")
            latest_build, url, _ = hangar_latest(namespace, slug, "PAPER")
        elif source.startswith("github:"):
            _, repo, asset_key = source.split(":")
            if asset_key == "Vanilla":
                latest_build, url = github_release_asset(repo, r"Vanilla\.jar$")
            elif asset_key == "EssentialsX":
                latest_build, url = github_release_asset(
                    repo, r"^EssentialsX-[\d.]+\.jar$"
                )
            else:
                raise RuntimeError(f"Unknown github asset key: {asset_key}")
        else:
            raise RuntimeError(f"Unknown source: {source}")

        dest = plugins_dir / output_name
        stored = state.get("plugins", {}).get(output_name, {})
        current_hash = sha256_file(dest)
        changed = stored.get("build") != latest_build or current_hash is None or not dest.is_file()
        items.append(
            UpdateItem(
                name=name,
                path=dest,
                current_build=stored.get("build"),
                latest_build=latest_build,
                download_url=url,
                output_name=output_name,
                changed=changed,
            )
        )

    return items


def download_paper(item: UpdateItem) -> str:
    _, _, expected_sha = paper_latest()
    request = urllib.request.Request(item.download_url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        data = response.read()
    if len(data) < 5_000_000:
        raise RuntimeError("Paper download too small")
    actual_sha = hashlib.sha256(data).hexdigest()
    if actual_sha != expected_sha:
        raise RuntimeError("Paper SHA256 mismatch")
    tmp = item.path.with_suffix(item.path.suffix + ".tmp")
    tmp.write_bytes(data)
    tmp.replace(item.path)
    return actual_sha


def apply_updates(root: Path, items: list[UpdateItem], force: bool = False) -> dict[str, Any]:
    server_dir = root / "server"
    plugins_dir = server_dir / "plugins"
    backup_dir = server_dir / "backups" / datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    state_path = server_dir / ".update-state.json"
    state = load_state(state_path)

    plugins_dir.mkdir(parents=True, exist_ok=True)
    updated: list[str] = []

    for item in items:
        if not item.changed and not force:
            continue

        if item.path.is_file():
            backup_dir.mkdir(parents=True, exist_ok=True)
            backup_target = backup_dir / item.path.name
            backup_target.write_bytes(item.path.read_bytes())

        if item.name == "Paper":
            file_hash = download_paper(item)
            state["paper"] = {
                "version": PAPER_VERSION,
                "build": item.latest_build,
                "sha256": file_hash,
            }
        else:
            download_file(item.download_url, item.path)
            verify_jar(item.path)
            file_hash = sha256_file(item.path)
            state.setdefault("plugins", {})[item.output_name] = {
                "build": item.latest_build,
                "sha256": file_hash,
            }
            if item.output_name == "StaffPlusPlus.jar":
                for old in plugins_dir.glob("StaffPlusPlus-*.jar"):
                    if old.name != item.output_name:
                        old.unlink()

        updated.append(item.name)

    save_state(state_path, state)
    return {"updated": updated, "backup_dir": str(backup_dir) if updated else None}


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Pisces SMP auto-updater")
    parser.add_argument("--check", action="store_true", help="Only show pending updates")
    parser.add_argument("--force", action="store_true", help="Re-download everything")
    parser.add_argument("--json", action="store_true", help="Machine-readable output")
    parser.add_argument("--root", default=None, help="Project root path")
    args = parser.parse_args()

    root = Path(args.root).resolve() if args.root else Path(__file__).resolve().parent.parent
    items = build_plan(root)
    if args.force:
        for item in items:
            item.changed = True

    pending = [item for item in items if item.changed]

    if args.check:
        if args.json:
            print(
                json.dumps(
                    [
                        {
                            "name": item.name,
                            "current": item.current_build,
                            "latest": item.latest_build,
                            "path": str(item.path),
                        }
                        for item in pending
                    ],
                    indent=2,
                )
            )
        else:
            if not pending:
                print("All components up to date.")
            else:
                print("Updates available:")
                for item in pending:
                    current = item.current_build or "not installed"
                    print(f"  {item.name}: {current} -> {item.latest_build}")
        return 0

    if not pending:
        print("All components up to date.")
        return 0

    result = apply_updates(root, items, force=args.force)
    print(f"Updated: {', '.join(result['updated'])}")
    if result["backup_dir"]:
        print(f"Backups: {result['backup_dir']}")
    print("Restart the server to load updates.")
    return 10


if __name__ == "__main__":
    sys.exit(main())
