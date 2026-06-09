#!/usr/bin/env python3
"""
Azure DevOps PR watcher daemon for Caelestia bar.

Polls configured Azure DevOps project for active PRs across all enabled repos,
writes state to ~/.local/state/caelestia/git-watcher-state.json, and sends
desktop notifications for new PRs, overdue PRs (> threshold), and PR comments
or mentions targeting the configured identity.

Config: ~/.config/caelestia/git-watcher.json
State:  ~/.local/state/caelestia/git-watcher-state.json
Repos:  ~/.local/state/caelestia/git-watcher-repos.json
PID:    ~/.local/state/caelestia/git-watcher.pid
"""

import base64
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
HOME = os.path.expanduser("~")
CONFIG_PATH = os.path.join(HOME, ".config", "caelestia", "git-watcher.json")
STATE_DIR = os.path.join(HOME, ".local", "state", "caelestia")
STATE_PATH = os.path.join(STATE_DIR, "git-watcher-state.json")
REPOS_PATH = os.path.join(STATE_DIR, "git-watcher-repos.json")
DISCORD_PATH = os.path.join(STATE_DIR, "git-watcher-discord.json")
MUTED_PATH = os.path.join(STATE_DIR, "git-watcher-muted.json")
PID_PATH = os.path.join(STATE_DIR, "git-watcher.pid")

os.makedirs(STATE_DIR, exist_ok=True)

# ---------------------------------------------------------------------------
# Globals (reloaded on SIGHUP)
# ---------------------------------------------------------------------------
_config = {}
_lock = threading.Lock()
_stop_event = threading.Event()

# Track state across polls to detect new/changed items
_repos_refresh_counter: int = 0    # Refresh full repo list every N polls for config UI

_seen_pr_ids: set = set()          # PRs we've already notified about (new PR)
_pr_first_seen: dict = {}          # pr_id -> datetime when first observed active
_pr_last_updated: dict = {}        # pr_id -> lastUpdatedDate string from API
_overdue_notified: set = set()     # pr_ids for which overdue notif was sent
_mention_notified: set = set()     # "pr_id:thread_id" for sent mention notifs
_comment_notified: set = set()     # "pr_id:thread_id" for sent comment notifs (owned PRs)

# Discord-first: hold new-PR notifications until the link appears in a watched channel
_discord_pending_prs: dict = {}   # pr_id -> (summary, body)
_discord_last_msg_id: dict = {}   # channel_id -> newest processed Discord message snowflake

# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------

def load_config() -> dict:
    try:
        with open(CONFIG_PATH) as f:
            cfg = json.load(f)
        return cfg
    except Exception as e:
        _write_error(f"Failed to load config: {e}")
        return {}


def get_cfg(key, default=None):
    return _config.get(key, default)


def _auth_header() -> str:
    pat = get_cfg("pat", "")
    if not pat:
        return ""
    encoded = base64.b64encode(f":{pat}".encode()).decode()
    return f"Basic {encoded}"


# ---------------------------------------------------------------------------
# Azure DevOps REST helpers
# ---------------------------------------------------------------------------

def _api_get(url: str) -> dict | list | None:
    auth = _auth_header()
    if not auth:
        return None
    req = urllib.request.Request(url, headers={
        "Authorization": auth,
        "Accept": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        print(f"[git-watcher] HTTP {e.code} for {url}: {body[:200]}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"[git-watcher] Request failed for {url}: {e}", file=sys.stderr)
        return None


def _org_url() -> str:
    return get_cfg("organizationUrl", "").rstrip("/")


def _project_url(project: str) -> str:
    return f"{_org_url()}/{project}"


def fetch_projects() -> list[str]:
    """Return list of project names in the organization."""
    url = f"{_org_url()}/_apis/projects?$top=200&api-version=7.1"
    data = _api_get(url)
    if not data:
        return []
    return [p["name"] for p in data.get("value", [])]


def fetch_repos_for_project(project: str) -> list[dict]:
    url = f"{_project_url(project)}/_apis/git/repositories?api-version=7.1"
    data = _api_get(url)
    if not data:
        return []
    return data.get("value", [])


def fetch_all_repos_grouped() -> list[dict]:
    """Return [{project, repos: [{id, name}]}] for all projects (config UI use only)."""
    projects = fetch_projects()
    result = []
    for proj in projects:
        repos = fetch_repos_for_project(proj)
        if repos:
            valid = [{"id": r["id"], "name": r["name"]}
                     for r in repos if r.get("id") and r.get("name")]
            if valid:
                result.append({"project": proj, "repos": valid})
    return result


def fetch_watched_repos_grouped() -> list[dict]:
    """Return [{project, repos}] for ONLY the repos in watchedRepos.

    Much cheaper than fetch_all_repos_grouped() — one API call per watched
    project instead of fetching all 100+ repos from every project. Called on
    every poll; the full list is refreshed separately for the config UI.
    """
    watched: list = get_cfg("watchedRepos", [])
    if not watched:
        return []

    # Build {project: {repo_name, ...}} from watchedRepos list
    by_project: dict = {}
    for entry in watched:
        if "/" in entry:
            proj, repo_name = entry.split("/", 1)
        else:
            proj = ""
            repo_name = entry
        by_project.setdefault(proj, set()).add(repo_name)

    result = []
    for proj, wanted_names in by_project.items():
        if not proj:
            continue
        repos = fetch_repos_for_project(proj)
        valid = [{"id": r["id"], "name": r["name"]}
                 for r in repos
                 if r.get("id") and r.get("name") and r["name"] in wanted_names]
        if valid:
            result.append({"project": proj, "repos": valid})
    return result


def fetch_active_prs(project: str, repo_id: str) -> list[dict]:
    url = (
        f"{_project_url(project)}/_apis/git/repositories/{repo_id}/pullrequests"
        f"?searchCriteria.status=active&api-version=7.1"
    )
    data = _api_get(url)
    if not data:
        return []
    return data.get("value", [])


def fetch_pr_threads(project: str, repo_id: str, pr_id: int) -> list[dict]:
    url = (
        f"{_project_url(project)}/_apis/git/repositories/{repo_id}"
        f"/pullrequests/{pr_id}/threads?api-version=7.1"
    )
    data = _api_get(url)
    if not data:
        return []
    return data.get("value", [])


def fetch_completed_prs(project: str, repo_id: str, top: int = 3) -> list[dict]:
    url = (
        f"{_project_url(project)}/_apis/git/repositories/{repo_id}/pullrequests"
        f"?searchCriteria.status=completed&$top={top}&api-version=7.1"
    )
    data = _api_get(url)
    if not data:
        return []
    return data.get("value", [])


def _load_muted() -> tuple[set, set]:
    """Return (muted_ids, dismissed_ids) from the muted state file."""
    try:
        with open(MUTED_PATH) as f:
            d = json.load(f)
        return set(d.get("muted", [])), set(d.get("dismissed", []))
    except Exception:
        return set(), set()


# ---------------------------------------------------------------------------
# Discord REST helpers
# ---------------------------------------------------------------------------

_DISCORD_API = "https://discord.com/api/v10"
_PR_URL_RE = re.compile(r'pullrequest/(\d+)', re.IGNORECASE)


def _discord_api_get(path: str, token: str) -> dict | list | None:
    url = f"{_DISCORD_API}{path}"
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bot {token}",
        "User-Agent": "git-watcher (https://github.com, 1.0)",
        "Accept": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        print(f"[git-watcher] Discord HTTP {e.code} for {path}: {body[:200]}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"[git-watcher] Discord request failed for {path}: {e}", file=sys.stderr)
        return None


def discord_fetch_guilds(token: str) -> list[dict]:
    data = _discord_api_get("/users/@me/guilds", token)
    if not isinstance(data, list):
        return []
    return [{"id": g["id"], "name": g["name"]} for g in data]


def discord_fetch_channels(token: str, guild_id: str) -> list[dict]:
    data = _discord_api_get(f"/guilds/{guild_id}/channels", token)
    if not isinstance(data, list):
        return []
    # type 0 = GUILD_TEXT, type 5 = GUILD_NEWS
    return [{"id": c["id"], "name": c["name"]}
            for c in data if c.get("type") in (0, 5)]


def discord_fetch_channels_grouped(token: str) -> list[dict]:
    """Return [{guild_id, guild_name, channels: [{id, name}]}] for the config UI."""
    result = []
    for guild in discord_fetch_guilds(token):
        channels = discord_fetch_channels(token, guild["id"])
        if channels:
            result.append({
                "guild_id": guild["id"],
                "guild_name": guild["name"],
                "channels": channels,
            })
    return result


def discord_fetch_messages(token: str, channel_id: str, after: str = None) -> list[dict]:
    path = f"/channels/{channel_id}/messages?limit=50"
    if after:
        path += f"&after={after}"
    data = _discord_api_get(path, token)
    if not isinstance(data, list):
        return []
    return data


def _poll_discord() -> set:
    """Poll watched Discord channels; return set of PR IDs found in new messages."""
    dc = get_cfg("discordFirst", {})
    token = dc.get("token", "")
    channel_ids = dc.get("channels", [])
    if not token or not channel_ids:
        return set()

    found: set = set()
    for ch_id in channel_ids:
        after = _discord_last_msg_id.get(ch_id)
        messages = discord_fetch_messages(token, ch_id, after=after)
        if not messages:
            continue
        # Track the newest message ID regardless of return order
        newest_id = max((m["id"] for m in messages), key=lambda x: int(x))
        _discord_last_msg_id[ch_id] = newest_id
        for msg in messages:
            for match in _PR_URL_RE.finditer(msg.get("content", "")):
                found.add(int(match.group(1)))
    return found


# ---------------------------------------------------------------------------
# Notification helpers
# ---------------------------------------------------------------------------

_SOUND_PATHS = {
    "message": "/usr/share/sounds/freedesktop/stereo/message.oga",
}

# Icon paths — prefer Papirus-Dark (active theme) with fallback to Adwaita symbolic
def _resolve_icon(name: str) -> str:
    """Return full icon file path for notify-send, falling back to icon name."""
    candidates = [
        f"/usr/share/icons/Papirus-Dark/24x24/actions/{name}.svg",
        f"/usr/share/icons/Papirus-Dark/24x24/status/{name}.svg",
        f"/usr/share/icons/Papirus/24x24/actions/{name}.svg",
        f"/usr/share/icons/Adwaita/symbolic/actions/{name}-symbolic.svg",
        f"/usr/share/icons/Adwaita/symbolic/status/{name}-symbolic.svg",
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    return name  # fallback to name-based lookup


def _play_sound(kind: str = "message") -> None:
    path = _SOUND_PATHS.get(kind, _SOUND_PATHS["message"])
    if os.path.exists(path):
        try:
            subprocess.Popen(["paplay", path],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            print(f"[git-watcher] paplay failed: {e}", file=sys.stderr)


def _notify(summary: str, body: str, urgency: str = "normal",
            expire_ms: int = 5000, icon: str = "mail-message-new",
            sound: str = "message") -> None:
    """Send a desktop notification and play a sound."""
    args = [
        "notify-send",
        "--app-name", "GitWatcher",
        "--urgency", urgency,
        "--expire-time", str(expire_ms),
        "--icon", _resolve_icon(icon),
        summary,
        body,
    ]
    try:
        subprocess.Popen(args)
        _play_sound(sound)
    except Exception as e:
        print(f"[git-watcher] notify-send failed: {e}", file=sys.stderr)


def _notify_critical_with_action(summary: str, body: str, url: str,
                                  icon: str = "mail-message-new",
                                  sound: str = "message") -> None:
    """
    Send a critical non-expiring notification with an Open action.
    Blocks in a background thread until the user responds; opens the URL on click.
    """
    def _run():
        _play_sound(sound)
        args = [
            "notify-send",
            "--app-name", "GitWatcher",
            "--urgency", "critical",
            "--expire-time", "0",
            "--icon", _resolve_icon(icon),
            "--action", "default:Open PR",
            "--wait",
            summary,
            body,
        ]
        try:
            result = subprocess.run(args, capture_output=True, text=True, timeout=86400)
            if result.returncode == 0 and result.stdout.strip() == "default":
                subprocess.Popen(["xdg-open", url])
        except Exception as e:
            print(f"[git-watcher] critical notify failed: {e}", file=sys.stderr)

    t = threading.Thread(target=_run, daemon=True)
    t.start()


# ---------------------------------------------------------------------------
# PR processing helpers
# ---------------------------------------------------------------------------

def _pr_url(project: str, repo_name: str, pr_id: int) -> str:
    return f"{_org_url()}/{project}/_git/{repo_name}/pullrequest/{pr_id}"


def _should_watch(project: str, repo_name: str) -> bool:
    """True if this repo is in the watchedRepos allowlist. Empty list = watch nothing."""
    watched: list = get_cfg("watchedRepos", [])
    if not watched:
        return False
    qualified = f"{project}/{repo_name}"
    return qualified in watched or repo_name in watched


def _strip_branch(ref: str) -> str:
    return ref.removeprefix("refs/heads/")


def _parse_date(s: str) -> datetime | None:
    if not s:
        return None
    try:
        s = s.rstrip("Z")
        if "." in s:
            # Azure DevOps / .NET serializes DateTime with 7 fractional digits.
            # Python's %f only handles up to 6 — truncate to avoid ValueError.
            base, frac = s.rsplit(".", 1)
            s = f"{base}.{frac[:6]}"
            fmt = "%Y-%m-%dT%H:%M:%S.%f"
        else:
            fmt = "%Y-%m-%dT%H:%M:%S"
        return datetime.strptime(s, fmt).replace(tzinfo=timezone.utc)
    except Exception:
        return None


def _age_minutes(created_at: str) -> float:
    dt = _parse_date(created_at)
    if not dt:
        return 0.0
    delta = datetime.now(timezone.utc) - dt
    return delta.total_seconds() / 60.0


def _my_identity() -> str:
    return get_cfg("myIdentity", "").lower()


def _is_owned(pr: dict) -> bool:
    identity = _my_identity()
    if not identity:
        return False
    creator = pr.get("createdBy", {})
    unique = (creator.get("uniqueName") or "").lower()
    mail = (creator.get("mailAddress") or "").lower()
    return identity in (unique, mail)


def _is_reviewer(pr: dict) -> bool:
    identity = _my_identity()
    if not identity:
        return False
    for rv in pr.get("reviewers", []):
        unique = (rv.get("uniqueName") or "").lower()
        mail = (rv.get("mailAddress") or "").lower()
        if identity in (unique, mail):
            return True
    return False


def _has_mention(text: str) -> bool:
    identity = _my_identity()
    if not identity:
        return False
    # Azure DevOps @mentions appear as @<display name> or in HTML as <a href="...">@name</a>
    # Also check plain email presence in comment text
    username = identity.split("@")[0].lower()
    t = text.lower()
    return (f"@{username}" in t) or (identity in t)


# ---------------------------------------------------------------------------
# Main poll cycle
# ---------------------------------------------------------------------------

def _poll() -> dict:
    """
    Perform one poll cycle. Returns the state dict to write.
    """
    global _repos_refresh_counter

    overdue_minutes: int = get_cfg("notifications", {}).get("overdueMinutes", 60)
    notify_new_pr: bool = get_cfg("notifications", {}).get("newPr", True)
    notify_comment: bool = get_cfg("notifications", {}).get("prComment", True)
    notify_mention: bool = get_cfg("notifications", {}).get("prMention", True)
    discord_first: bool = get_cfg("discordFirst", {}).get("enabled", False)

    # Only fetch watched repos for PR polling — one API call per watched project
    # instead of fetching all 100+ repos across every project on each poll.
    grouped_repos = fetch_watched_repos_grouped()
    if not grouped_repos:
        return {"lastUpdated": _now_iso(), "error": "No repos configured — select repos in the GitWatcher config",
                "prs": [], "completedPrs": [], "overdueCount": 0, "mentionCount": 0,
                "commentItems": [], "mentionItems": []}

    # Refresh the full repo list (all projects, for config UI) every 10 polls
    _repos_refresh_counter += 1
    if _repos_refresh_counter >= 10 or not os.path.exists(REPOS_PATH):
        _repos_refresh_counter = 0
        full_repos = fetch_all_repos_grouped()
        if full_repos:
            _write_json(REPOS_PATH, full_repos)
        # Refresh the Discord guild/channel list for the config UI while the
        # feature is enabled and a token is set.
        discord_token = get_cfg("discordFirst", {}).get("token", "")
        if discord_first and discord_token:
            guilds = discord_fetch_channels_grouped(discord_token)
            if guilds:
                _write_json(DISCORD_PATH, guilds)

    muted_ids, dismissed_ids = _load_muted()

    active_pr_ids: set = set()
    result_prs = []
    completed_pr_list: list = []
    comment_items: list = []
    mention_items: list = []
    overdue_count = 0
    mention_count = 0

    for project_entry in grouped_repos:
        project = project_entry["project"]
        for repo in project_entry["repos"]:
            if not _should_watch(project, repo["name"]):
                continue

            prs = fetch_active_prs(project, repo["id"])
            for pr in prs:
                pr_id = pr["pullRequestId"]
                active_pr_ids.add(pr_id)

                created_at = pr.get("creationDate", "")
                if pr_id not in _pr_first_seen:
                    _pr_first_seen[pr_id] = datetime.now(timezone.utc)

                age_min = _age_minutes(created_at)
                last_source_commit = pr.get("lastMergeSourceCommit") or {}
                last_commit_date = (last_source_commit.get("author") or {}).get("date") or created_at
                stall_min = _age_minutes(last_commit_date)
                is_owned = _is_owned(pr)
                is_reviewer = _is_reviewer(pr)
                last_updated_commit = last_source_commit.get("commitId", "")
                pr_url = _pr_url(project, repo["name"], pr_id)

                is_approved = any(r.get("vote", 0) >= 5 for r in pr.get("reviewers", []))

                # Skip all notifications for muted or dismissed PRs
                suppressed = pr_id in muted_ids or pr_id in dismissed_ids

                # Detect new PR
                if pr_id not in _seen_pr_ids:
                    _seen_pr_ids.add(pr_id)
                    if notify_new_pr and not suppressed:
                        branch = _strip_branch(pr.get("sourceRefName", ""))
                        summary = f"New PR: {pr['title'][:60]}"
                        body = f"{repo['name']} → {_strip_branch(pr.get('targetRefName', ''))} | {branch}"
                        if discord_first:
                            # Hold the notification until the PR link is posted in
                            # a watched Discord channel (released in the poll below).
                            _discord_pending_prs[pr_id] = (summary, body)
                        else:
                            _notify(summary, body, icon="mail-message-new", sound="message")

                # Overdue = no approval AND stalled > threshold
                is_overdue = stall_min >= overdue_minutes and not is_approved
                if is_overdue and pr_id not in _overdue_notified:
                    _overdue_notified.add(pr_id)
                    if not suppressed:
                        h, m = int(stall_min // 60), int(stall_min % 60)
                        _notify_critical_with_action(
                            f"PR stalled {h}h {m}m without activity",
                            f"{pr['title'][:60]}\n{repo['name']}",
                            pr_url,
                            icon="dialog-warning",
                            sound="message",
                        )
                elif not is_overdue:
                    _overdue_notified.discard(pr_id)

                # Check threads for comments/mentions
                has_unread_comments = False
                has_mentions = False
                prev_updated = _pr_last_updated.get(pr_id)
                threads_changed = prev_updated != last_updated_commit

                if threads_changed and (is_owned or is_reviewer):
                    _pr_last_updated[pr_id] = last_updated_commit
                    threads = fetch_pr_threads(project, repo["id"], pr_id)
                    for thread in threads:
                        if thread.get("isDeleted"):
                            continue
                        thread_id = thread.get("id", 0)
                        for comment in thread.get("comments", []):
                            if comment.get("commentType") == "system":
                                continue
                            author = comment.get("author", {})
                            author_unique = (author.get("uniqueName") or "").lower()
                            author_mail = (author.get("mailAddress") or "").lower()
                            my = _my_identity()
                            is_mine = my in (author_unique, author_mail)
                            content = comment.get("content") or ""
                            key = f"{pr_id}:{thread_id}"

                            if _has_mention(content) and not is_mine:
                                has_mentions = True
                                feed_item = {
                                    "prId": pr_id,
                                    "prTitle": pr.get("title", ""),
                                    "repo": repo["name"],
                                    "project": project,
                                    "author": author.get("displayName", "Someone"),
                                    "excerpt": content[:120],
                                    "url": pr_url,
                                }
                                if feed_item not in mention_items:
                                    mention_items.append(feed_item)
                                if notify_mention and key not in _mention_notified and not suppressed:
                                    _mention_notified.add(key)
                                    _notify_critical_with_action(
                                        f"Mentioned in: {pr['title'][:50]}",
                                        f"{author.get('displayName', 'Someone')} in {repo['name']}",
                                        pr_url,
                                        icon="mail-message-new",
                                        sound="message",
                                    )

                            if is_owned and not is_mine:
                                has_unread_comments = True
                                feed_item = {
                                    "prId": pr_id,
                                    "prTitle": pr.get("title", ""),
                                    "repo": repo["name"],
                                    "project": project,
                                    "author": author.get("displayName", "Someone"),
                                    "excerpt": content[:120],
                                    "url": pr_url,
                                }
                                if feed_item not in comment_items:
                                    comment_items.append(feed_item)
                                if notify_comment and key not in _comment_notified and not suppressed:
                                    _comment_notified.add(key)
                                    _notify(
                                        f"Comment on your PR",
                                        f"{author.get('displayName', 'Someone')}: {content[:80]}",
                                        icon="mail-message-new",
                                        sound="message",
                                    )
                else:
                    for prev in result_prs:
                        if prev.get("id") == pr_id:
                            has_unread_comments = prev.get("hasUnreadComments", False)
                            has_mentions = prev.get("hasMentions", False)
                            break

                if is_overdue:
                    overdue_count += 1
                if has_mentions:
                    mention_count += 1

                result_prs.append({
                    "id": pr_id,
                    "title": pr.get("title", ""),
                    "repo": repo["name"],
                    "project": project,
                    "sourceBranch": _strip_branch(pr.get("sourceRefName", "")),
                    "targetBranch": _strip_branch(pr.get("targetRefName", "")),
                    "status": pr.get("status", "active"),
                    "createdAt": created_at,
                    "url": pr_url,
                    "ageMinutes": int(age_min),
                    "stallMinutes": int(stall_min),
                    "isOverdue": is_overdue,
                    "isApproved": is_approved,
                    "hasUnreadComments": has_unread_comments,
                    "hasMentions": has_mentions,
                    "isOwned": is_owned,
                    "isReviewer": is_reviewer,
                })

    # Collect completed PRs for archive tab (last 3 per watched repo, cap 20 total)
    for project_entry in grouped_repos:
        project = project_entry["project"]
        for repo in project_entry["repos"]:
            if not _should_watch(project, repo["name"]):
                continue
            for pr in fetch_completed_prs(project, repo["id"], top=3):
                pr_id_c = pr["pullRequestId"]
                completed_pr_list.append({
                    "id": pr_id_c,
                    "title": pr.get("title", ""),
                    "repo": repo["name"],
                    "project": project,
                    "sourceBranch": _strip_branch(pr.get("sourceRefName", "")),
                    "targetBranch": _strip_branch(pr.get("targetRefName", "")),
                    "status": "completed",
                    "url": _pr_url(project, repo["name"], pr_id_c),
                    "ageMinutes": int(_age_minutes(pr.get("creationDate", ""))),
                })
            if len(completed_pr_list) >= 20:
                break
        if len(completed_pr_list) >= 20:
            break

    # Discord-first: poll watched channels and release any held new-PR
    # notifications whose PR link has now appeared in Discord.
    if discord_first:
        confirmed = _poll_discord()
        for pid in list(_discord_pending_prs):
            if pid in confirmed:
                summary, body = _discord_pending_prs.pop(pid)
                _notify(summary, body, icon="mail-message-new", sound="message")
        # Drop held notifications for PRs that are no longer active on Azure.
        for pid in list(_discord_pending_prs):
            if pid not in active_pr_ids:
                _discord_pending_prs.pop(pid, None)

    # Clean up tracking state for PRs no longer active
    gone = set(_seen_pr_ids) - active_pr_ids
    for gid in gone:
        _seen_pr_ids.discard(gid)
        _pr_first_seen.pop(gid, None)
        _pr_last_updated.pop(gid, None)
        # Keep overdue/mention sets (don't re-notify if PR briefly disappears and comes back)

    # Hard filter: only keep PRs from repos in watchedRepos.
    # This is a defensive safeguard — result_prs should already only contain
    # watched repos, but this prevents stale/unexpected data from leaking through.
    watched_set = set(get_cfg("watchedRepos", []))
    if watched_set:
        result_prs = [
            pr for pr in result_prs
            if f"{pr.get('project','')}/{pr.get('repo','')}" in watched_set
            or pr.get("repo", "") in watched_set
        ]
        overdue_count = sum(1 for pr in result_prs if pr.get("isOverdue"))
        mention_count = sum(1 for pr in result_prs if pr.get("hasMentions"))

    return {
        "lastUpdated": _now_iso(),
        "error": None,
        "prs": result_prs,
        "completedPrs": completed_pr_list[:20],
        "overdueCount": overdue_count,
        "mentionCount": mention_count,
        "commentItems": comment_items[-20:],
        "mentionItems": mention_items[-20:],
    }


# ---------------------------------------------------------------------------
# Utility writers
# ---------------------------------------------------------------------------

def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _write_json(path: str, data):
    tmp = path + ".tmp"
    try:
        with open(tmp, "w") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, path)
    except Exception as e:
        print(f"[git-watcher] write {path} failed: {e}", file=sys.stderr)


def _write_error(msg: str):
    _write_json(STATE_PATH, {
        "lastUpdated": _now_iso(),
        "error": msg,
        "prs": [],
        "completedPrs": [],
        "overdueCount": 0,
        "mentionCount": 0,
        "commentItems": [],
        "mentionItems": [],
    })


# ---------------------------------------------------------------------------
# Signal handling
# ---------------------------------------------------------------------------

def _on_sighup(signum, frame):
    """Reload config and force repo-list refresh on SIGHUP."""
    global _config, _repos_refresh_counter
    print("[git-watcher] SIGHUP received — reloading config", file=sys.stderr)
    _config = load_config()
    _repos_refresh_counter = 10  # force full repo list refresh next poll


def _on_sigterm(signum, frame):
    print("[git-watcher] SIGTERM received — shutting down", file=sys.stderr)
    _stop_event.set()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    global _config

    # Write PID file
    try:
        with open(PID_PATH, "w") as f:
            f.write(str(os.getpid()))
    except Exception as e:
        print(f"[git-watcher] PID write failed: {e}", file=sys.stderr)

    signal.signal(signal.SIGHUP, _on_sighup)
    signal.signal(signal.SIGTERM, _on_sigterm)

    _config = load_config()
    if not _config:
        _write_error("Config not found or invalid. Run init-git-watcher.sh first.")
        sys.exit(1)

    pat = get_cfg("pat", "")
    if not pat:
        _write_error("No PAT configured. Open the GitWatcher config and enter your PAT.")
        sys.exit(1)

    print("[git-watcher] starting", file=sys.stderr)

    while not _stop_event.is_set():
        try:
            state = _poll()
            _write_json(STATE_PATH, state)
        except Exception as e:
            print(f"[git-watcher] poll error: {e}", file=sys.stderr)
            _write_error(f"Poll error: {e}")

        interval = int(get_cfg("pollIntervalSeconds", 60))
        _stop_event.wait(timeout=max(10, interval))

    # Cleanup PID file on exit
    try:
        os.unlink(PID_PATH)
    except Exception:
        pass


if __name__ == "__main__":
    # One-shot: fetch the Discord guild/channel list and write it for the config
    # UI, then exit. Token is passed as argv (or via GW_DISCORD_TOKEN) so the
    # config form can load channels before the config is saved.
    if len(sys.argv) >= 2 and sys.argv[1] == "--fetch-discord-channels":
        tok = sys.argv[2] if len(sys.argv) >= 3 else os.environ.get("GW_DISCORD_TOKEN", "")
        guilds = discord_fetch_channels_grouped(tok) if tok else []
        _write_json(DISCORD_PATH, guilds)
        sys.exit(0)
    main()
