#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


def cap_class(s: str) -> str:
    s = (s or "").strip()
    if not s:
        return "?"
    return s[0].upper() + s[1:].lower() if len(s) > 1 else s.upper()


def norm(s: str) -> str:
    return (
        s.replace(" — ", " - ")
        .replace("—", " - ")
        .replace(" – ", " - ")
        .strip()
    )


def parts_from_title(title: str) -> list[str]:
    t = norm(title or "")
    return [p.strip() for p in t.split(" - ") if p.strip()]


def pop_trailing_app(parts: list[str], klass: str, initial_class: str) -> list[str]:
    k = (klass or "").lower()
    ic = (initial_class or "").lower()
    out = list(parts)
    while out:
        last = out[-1].lower().rstrip(".")
        if k == "firefox" and (last.startswith("mozilla fi") or "mozilla firefox" in last):
            out.pop()
            continue
        if last == k:
            out.pop()
            continue
        if ic and last == ic:
            out.pop()
            continue
        break
    return out


def invert(parts: list[str]) -> list[str]:
    if len(parts) <= 1:
        return parts
    return list(reversed(parts))


def display_line(klass: str, initial_class: str, title: str) -> str:
    head = cap_class(klass)
    parts = parts_from_title(title)
    parts = pop_trailing_app(parts, klass, initial_class)
    parts = invert(parts)
    tail = " - ".join(parts) if parts else ""
    return f"{head} - {tail}" if tail else head


def sorted_rows(clients: list) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    for c in clients:
        if not isinstance(c, dict):
            continue
        if not c.get("mapped") or c.get("hidden"):
            continue
        addr = c.get("address")
        if not addr:
            continue
        line = display_line(
            str(c.get("class") or ""),
            str(c.get("initialClass") or ""),
            str(c.get("title") or ""),
        )
        rows.append((str(addr), line))
    rows.sort(key=lambda r: r[1].lower())
    return rows


def cmd_list() -> None:
    data = json.load(sys.stdin)
    rows = sorted_rows(data)
    sys.stdout.write("\n".join(f"{a}\t{d}" for a, d in rows) + ("\n" if rows else ""))


def norm_match(text: str) -> str:
    return re.sub(r"\s+", " ", (text or "").lower()).strip()


def title_match_score(title: str, summary: str, body: str) -> int:
    title_norm = norm_match(title)
    if not title_norm:
        return 0
    su = norm_match(summary)
    b = norm_match(body)
    if su and (title_norm in su or su in title_norm):
        return 100
    if len(b) >= 8 and b[:80] in title_norm:
        return 80
    score = 0
    for word in su.split():
        if len(word) < 3:
            continue
        if word in title_norm:
            score += 12
    return score


def word_overlap_score(title: str, summary: str, body: str) -> int:
    title_norm = norm_match(title)
    if not title_norm:
        return 0
    text = norm_match(f"{summary} {body}")
    score = 0
    for word in re.split(r"[^a-z0-9]+", text):
        if len(word) < 4:
            continue
        if word in title_norm:
            score += len(word)
    return score


def client_score(client: dict, summary: str, body: str) -> int:
    title = str(client.get("title") or client.get("initialTitle") or "")
    return title_match_score(title, summary, body) * 1000 + word_overlap_score(
        title, summary, body
    )


def listable_clients(clients: list) -> list[dict]:
    out: list[dict] = []
    for c in clients:
        if not isinstance(c, dict):
            continue
        if not c.get("mapped") or c.get("hidden"):
            continue
        addr = c.get("address")
        if not addr:
            continue
        out.append(c)
    return out


def needles_for_app(desktop_entry: str, app_name: str) -> list[str]:
    needles: list[str] = []
    if desktop_entry:
        needles.append(desktop_entry.replace(".desktop", "").lower())
    if app_name:
        needles.append(app_name.lower())
    return [n for n in needles if len(n) >= 2]


def class_matches(client: dict, needles: list[str]) -> bool:
    if not needles:
        return False
    klass = norm_match(str(client.get("class") or client.get("initialClass") or ""))
    title = norm_match(str(client.get("title") or client.get("initialTitle") or ""))
    return any(n in klass or n in title for n in needles)


def pick_best(clients: list[dict], summary: str, body: str) -> dict | None:
    if not clients:
        return None
    if len(clients) == 1:
        return clients[0]
    best = max(clients, key=lambda c: client_score(c, summary, body))
    return best if client_score(best, summary, body) > 0 else None


def resolve_focus_client(
    pid: int, desktop_entry: str, app_name: str, summary: str, body: str
) -> dict | None:
    raw = subprocess.check_output(["hyprctl", "clients", "-j"], text=True)
    clients = listable_clients(json.loads(raw))
    if not clients:
        return None

    if pid > 0:
        pid_matches = [c for c in clients if c.get("pid") == pid]
        if len(pid_matches) == 1:
            return pid_matches[0]
        picked = pick_best(pid_matches, summary, body)
        if picked:
            return picked

    picked = pick_best(clients, summary, body)
    if picked and title_match_score(
        str(picked.get("title") or picked.get("initialTitle") or ""),
        summary,
        body,
    ) >= 12:
        return picked

    needles = needles_for_app(desktop_entry, app_name)
    class_matches_list = [c for c in clients if class_matches(c, needles)]
    return pick_best(class_matches_list, summary, body)


def focus_address(addr: str) -> int:
    script = Path(__file__).with_name("hypr-focus-window.sh")
    return subprocess.run(["bash", str(script), str(addr)], check=False).returncode


def cmd_focus_notif(args: argparse.Namespace) -> int:
    client = resolve_focus_client(
        args.pid,
        args.desktop or "",
        args.app or "",
        args.summary or "",
        args.body or "",
    )
    if not client:
        return 1
    addr = client.get("address")
    if not addr:
        return 1
    return focus_address(str(addr))


def cmd_cycle(direction: str) -> None:
    raw = subprocess.check_output(["hyprctl", "clients", "-j"], text=True)
    clients = json.loads(raw)
    rows = sorted_rows(clients)
    addrs = [a for a, _ in rows]
    if not addrs:
        return
    aw_raw = subprocess.check_output(["hyprctl", "activewindow", "-j"], text=True).strip()
    curr = None
    if aw_raw and aw_raw != "null":
        try:
            aw = json.loads(aw_raw)
            curr = aw.get("address")
        except json.JSONDecodeError:
            pass
    if curr and curr in addrs:
        i = addrs.index(curr)
        if direction == "prev":
            nxt = addrs[(i - 1 + len(addrs)) % len(addrs)]
        else:
            nxt = addrs[(i + 1) % len(addrs)]
    else:
        nxt = addrs[0]
    subprocess.run(
        ["hyprctl", "dispatch", f"focuswindow address:{nxt}"],
        check=False,
    )


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(2)
    cmd = sys.argv[1]
    if cmd == "list":
        cmd_list()
    elif cmd == "cycle" and len(sys.argv) >= 3:
        d = sys.argv[2]
        if d not in ("next", "prev"):
            sys.exit(2)
        cmd_cycle(d)
    elif cmd == "focus-notif":
        parser = argparse.ArgumentParser(prog="window_menu.py focus-notif")
        parser.add_argument("--pid", type=int, default=0)
        parser.add_argument("--desktop", default="")
        parser.add_argument("--app", default="")
        parser.add_argument("--summary", default="")
        parser.add_argument("--body", default="")
        args = parser.parse_args(sys.argv[2:])
        sys.exit(cmd_focus_notif(args))
    else:
        sys.exit(2)


if __name__ == "__main__":
    main()
