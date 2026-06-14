#!/usr/bin/env python3

import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request


API_ROOT = "https://api.github.com"


def env_bool(name, default=False):
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in ("1", "true", "yes", "y", "on")


def env_int(name, default):
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    try:
        return int(value)
    except ValueError:
        print(f"invalid integer for {name}: {value}", file=sys.stderr)
        sys.exit(2)


def require_env(name):
    value = os.environ.get(name)
    if not value:
        print(f"missing required environment variable: {name}", file=sys.stderr)
        sys.exit(2)
    return value


TOKEN = require_env("GITHUB_TOKEN")
REPOSITORY = require_env("GITHUB_REPOSITORY")
DRY_RUN = env_bool("CLEAN_DRY_RUN", False)
KEEP_FIRMWARE_PER_CONFIG = max(0, env_int("KEEP_FIRMWARE_PER_CONFIG", 1))


def request(method, url_or_path, data=None, ok=(200,)):
    if url_or_path.startswith(("http://", "https://")):
        url = url_or_path
    else:
        url = f"{API_ROOT}{url_or_path}"

    body = None
    if data is not None:
        body = json.dumps(data).encode()

    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if body is not None:
        req.add_header("Content-Type", "application/json")

    with urllib.request.urlopen(req) as response:
        payload = response.read()
        if response.status not in ok:
            raise RuntimeError(f"{method} {url} returned {response.status}")
        if not payload:
            return None, response.headers
        return json.loads(payload.decode()), response.headers


def next_link(headers):
    link_header = headers.get("Link", "")
    for part in link_header.split(","):
        url_part, _, rel_part = part.partition(";")
        if 'rel="next"' in rel_part:
            return url_part.strip()[1:-1]
    return None


def paginate(path, array_key=None):
    url = path
    while url:
        data, headers = request("GET", url)
        items = data[array_key] if array_key else data
        for item in items:
            yield item
        url = next_link(headers)


def delete(path, label):
    if DRY_RUN:
        print(f"DRY-RUN delete {label}")
        return
    try:
        request("DELETE", path, ok=(204,))
        print(f"deleted {label}")
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            print(f"already gone {label}")
            return
        raise


def config_from_body(body):
    match = re.search(r"(?im)^Config:\s*([^\s]+)\s*$", body or "")
    return match.group(1) if match else None


def config_from_tag(tag):
    match = re.match(r"^(.+-MESH-(?:AC|AP))-[0-9a-fA-F]+-\d+$", tag)
    return match.group(1) if match else None


def test_config_only_from_body(body):
    match = re.search(r"(?im)^Test config only:\s*(true|false)\s*$", body or "")
    if not match:
        return None
    return match.group(1).lower() == "true"


def release_assets(release):
    return [asset.get("name", "") for asset in release.get("assets", [])]


def looks_like_config_only_by_assets(release):
    assets = release_assets(release)
    return bool(assets) and all(name.startswith("config-") and name.endswith(".txt") for name in assets)


def classify_release(release):
    tag = release["tag_name"]
    body = release.get("body") or ""
    config_name = config_from_body(body) or config_from_tag(tag)
    explicit_config_only = test_config_only_from_body(body)

    if explicit_config_only is True:
        return config_name, "config-only"
    if explicit_config_only is False:
        return config_name, "firmware"
    if config_name and looks_like_config_only_by_assets(release):
        return config_name, "config-only"
    if config_name:
        return config_name, "firmware"
    return None, "unmanaged"


def delete_release_and_tag(release, reason):
    tag = release["tag_name"]
    release_id = release["id"]
    delete(f"/repos/{REPOSITORY}/releases/{release_id}", f"release {tag} ({reason})")
    encoded_tag = urllib.parse.quote(tag, safe="")
    delete(f"/repos/{REPOSITORY}/git/refs/tags/{encoded_tag}", f"tag {tag} ({reason})")


def clean_releases():
    releases = list(paginate(f"/repos/{REPOSITORY}/releases?per_page=100"))
    full_by_config = {}
    delete_plan = []
    delete_ids = set()

    for release in releases:
        config_name, kind = classify_release(release)
        if kind == "config-only":
            delete_plan.append((release, "config-only"))
            delete_ids.add(release["id"])
        elif kind == "firmware" and config_name:
            full_by_config.setdefault(config_name, []).append(release)
        else:
            print(f"skip unmanaged release {release['tag_name']}")

    for config_name, config_releases in sorted(full_by_config.items()):
        config_releases.sort(key=lambda item: item["created_at"], reverse=True)
        keep = config_releases[:KEEP_FIRMWARE_PER_CONFIG]
        remove = config_releases[KEEP_FIRMWARE_PER_CONFIG:]
        kept_tags = ", ".join(item["tag_name"] for item in keep) or "none"
        print(f"keep firmware releases for {config_name}: {kept_tags}")
        for release in remove:
            if release["id"] not in delete_ids:
                delete_plan.append((release, f"old firmware for {config_name}"))
                delete_ids.add(release["id"])

    print(f"release cleanup candidates: {len(delete_plan)}")
    for release, reason in delete_plan:
        delete_release_and_tag(release, reason)


def clean_workflow_runs():
    runs = list(paginate(f"/repos/{REPOSITORY}/actions/runs?status=completed&per_page=100", "workflow_runs"))
    print(f"completed workflow runs cleanup candidates: {len(runs)}")
    for run in runs:
        run_id = run["id"]
        name = run.get("name") or "workflow"
        conclusion = run.get("conclusion") or "unknown"
        delete(f"/repos/{REPOSITORY}/actions/runs/{run_id}", f"workflow run {run_id} {name} ({conclusion})")


def main():
    print(f"repository: {REPOSITORY}")
    print(f"dry run: {str(DRY_RUN).lower()}")
    print(f"keep firmware releases per config: {KEEP_FIRMWARE_PER_CONFIG}")
    clean_releases()
    clean_workflow_runs()


if __name__ == "__main__":
    main()
