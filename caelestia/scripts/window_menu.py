#!/usr/bin/env python3
import json
import subprocess
import sys


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
    else:
        sys.exit(2)


if __name__ == "__main__":
    main()
