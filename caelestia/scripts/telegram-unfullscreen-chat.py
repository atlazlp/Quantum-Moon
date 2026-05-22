#!/usr/bin/env python3
"""Clear Telegram chat fullscreen when the media viewer closes (Hyprland socket2, idle blocked read)."""
from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path


def clear_chat_fullscreen() -> None:
    try:
        raw = subprocess.check_output(["hyprctl", "clients", "-j"], text=True)
        clients = json.loads(raw)
    except (subprocess.CalledProcessError, json.JSONDecodeError, FileNotFoundError):
        return

    for client in clients:
        if client.get("class") != "org.telegram.desktop":
            continue
        if client.get("title") == "Media viewer":
            continue
        if (client.get("fullscreen") or 0) <= 0 and (client.get("fullscreenClient") or 0) <= 0:
            continue
        addr = client.get("address")
        if not addr:
            continue
        for args in (
            ["dispatch", "focuswindow", f"address:{addr}"],
            ["dispatch", "fullscreenstate", "internal", "0", "0"],
            ["dispatch", "fullscreenstate", "client", "0", "0"],
            ["dispatch", "fullscreen", "0"],
        ):
            subprocess.run(["hyprctl", *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main() -> int:
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig:
        return 0

    runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    sock_path = Path(runtime) / "hypr" / sig / ".socket2.sock"
    if not sock_path.is_socket():
        return 0

    lock = Path(runtime) / "telegram-unfullscreen-chat.lock"
    try:
        os.kill(int(lock.read_text().strip()), 0)
        return 0
    except (OSError, ValueError, FileNotFoundError):
        pass
    lock.write_text(str(os.getpid()))

    def schedule_clear() -> None:
        def run() -> None:
            time.sleep(0.08)
            clear_chat_fullscreen()

        threading.Thread(target=run, daemon=True).start()

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(str(sock_path))
    buf = b""
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            text = line.decode(errors="replace")
            if text.startswith("closewindow>>") or text == "fullscreen>>0":
                schedule_clear()

    return 0


if __name__ == "__main__":
    sys.exit(main())
