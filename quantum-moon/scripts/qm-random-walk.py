#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import random
import sys
from pathlib import Path


def _state_dir() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state")) / "quantum-moon"


def _qm_root() -> Path:
    return Path(__file__).resolve().parent.parent


def _list_slugs(modes_dir: Path) -> list[str]:
    if not modes_dir.is_dir():
        return []
    return sorted(p.name for p in modes_dir.iterdir() if p.is_dir())


def _read_json(path: Path, default):
    if not path.is_file():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return default


def pick_slug() -> str:
    qm = _qm_root()
    modes_dir = qm / "modes"
    all_slugs = _list_slugs(modes_dir)
    if not all_slugs:
        print("No modes under modes/", file=sys.stderr)
        sys.exit(1)

    state_dir = _state_dir()
    state_dir.mkdir(parents=True, exist_ok=True)
    current_path = state_dir / "current.json"
    current = ""
    if current_path.is_file():
        cur = _read_json(current_path, {})
        if isinstance(cur, dict):
            current = str(cur.get("slug") or "")

    rw_path = state_dir / "random-walk.json"
    data = _read_json(rw_path, {"history": []})
    hist = data.get("history")
    if not isinstance(hist, list):
        hist = []
    hist = [str(x) for x in hist if isinstance(x, (str, int, float))][-50:]

    ban: set[str] = set()
    if len(hist) >= 1:
        ban.add(hist[-1])
    if len(hist) >= 2:
        ban.add(hist[-2])

    tail9 = hist[-9:] if len(hist) >= 9 else hist[:]
    tail9_set = set(tail9)
    stale = [s for s in all_slugs if s not in tail9_set]

    def pool_from(candidates: list[str]) -> list[str]:
        return [s for s in candidates if s not in ban and s != current]

    pool = pool_from(stale)
    if not pool:
        pool = pool_from(all_slugs)
    if not pool:
        pool = [s for s in all_slugs if s != current]
    if not pool:
        pool = list(all_slugs)

    return random.choice(pool)


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] != "pick":
        print("usage: qm-random-walk.py pick", file=sys.stderr)
        sys.exit(1)
    print(pick_slug(), end="")


if __name__ == "__main__":
    main()
