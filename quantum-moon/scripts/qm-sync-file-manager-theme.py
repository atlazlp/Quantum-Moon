#!/usr/bin/env python3
import argparse
import configparser
import datetime
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import unquote, urlparse


SCHEME_FILE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "caelestia" / "scheme.json"
HYPR_SCHEME_CONF = (
    Path.home() / ".local" / "share" / "caelestia" / "hypr" / "scheme" / "current.conf"
)
HYPR_GROUPBAR_CONF = HYPR_SCHEME_CONF.parent / "groupbar.conf"
HYPR_SHADOW_CONF = HYPR_SCHEME_CONF.parent / "shadow.conf"
KDE_SCHEME_KEY = "CaelestiaQM"
KDE_SCHEME_FILE = KDE_SCHEME_KEY + ".colors"
GENERATED_CSS = Path.home() / ".config" / "caelestia" / "generated" / "qm-libadwaita.css"
GTK4_BLOCK_BEGIN = "/* BEGIN quantum-moon-gtk4 */"
GTK4_BLOCK_END = "/* END quantum-moon-gtk4 */"
GTK4_USER_BLOCK_RE = re.compile(
    re.escape(GTK4_BLOCK_BEGIN) + r".*?" + re.escape(GTK4_BLOCK_END) + r"\s*",
    re.DOTALL,
)
GTK4_LEGACY_IMPORT = re.compile(
    r"^\s*/\*\s*quantum-moon:\s*libadwaita\s*sync\s*\*/\s*\n\s*@import\s+url\([^)]*qm-libadwaita\.css[^)]*\)\s*;\s*\n?",
    re.MULTILINE | re.IGNORECASE,
)
GTK3_IMPORT_LINE = '/* quantum-moon: gtk3 sync */\n@import url("../caelestia/generated/qm-gtk3.css");\n'

KITTY_LISTEN_SOCK_NAME = "kitty-caelestia-qm.sock"
LISTEN_ON_RE = re.compile(r"^\s*listen_on\s+(.+)$", re.IGNORECASE | re.MULTILINE)


def expand_kitty_conf_vars(s: str) -> str:
    def repl(m: re.Match[str]) -> str:
        return os.environ.get(m.group(1), "")

    s = re.sub(r"\$\{([^}]+)\}", repl, s)
    return os.path.expandvars(s)


def default_qm_kitty_listen_address() -> str:
    rd = os.environ.get("XDG_RUNTIME_DIR")
    if not rd:
        rd = f"/run/user/{os.getuid()}"
    return f"unix:{Path(rd) / KITTY_LISTEN_SOCK_NAME}"


def normalize_kitty_listen_address(raw: str) -> str:
    raw = raw.strip()
    if not raw:
        return raw
    if raw.startswith(("unix:", "tcp:")):
        return raw
    if raw.startswith("@"):
        return f"unix:{raw}"
    if raw.startswith("/"):
        return f"unix:{raw}"
    return raw


def _kitty_pids() -> list[int]:
    out: list[int] = []
    proc = Path("/proc")
    try:
        entries = list(proc.iterdir())
    except OSError:
        return []
    for p in entries:
        if not p.name.isdigit():
            continue
        try:
            comm = (p / "comm").read_text().strip()
        except OSError:
            continue
        if comm == "kitty":
            try:
                out.append(int(p.name))
            except ValueError:
                continue
    out.sort()
    return out


def _read_proc_environ(pid: int) -> dict[str, str]:
    raw = Path(f"/proc/{pid}/environ").read_bytes()
    d: dict[str, str] = {}
    for entry in raw.split(b"\0"):
        if b"=" not in entry:
            continue
        k, _, v = entry.partition(b"=")
        d[k.decode("utf-8", errors="ignore")] = v.decode("utf-8", errors="ignore")
    return d


def kitty_rc_candidate_addresses(kitty_conf: Path) -> list[str]:
    order: list[str] = []
    seen: set[str] = set()

    def add(raw: str) -> None:
        addr = normalize_kitty_listen_address(expand_kitty_conf_vars(raw.strip()))
        if not addr or addr in seen:
            return
        seen.add(addr)
        order.append(addr)

    for pid in _kitty_pids():
        try:
            env = _read_proc_environ(pid)
        except OSError:
            continue
        if v := env.get("KITTY_LISTEN_ON"):
            add(v)
        if xdg := env.get("XDG_RUNTIME_DIR"):
            add(f"unix:{Path(xdg) / KITTY_LISTEN_SOCK_NAME}")

    if kitty_conf.is_file():
        m = LISTEN_ON_RE.search(kitty_conf.read_text(encoding="utf-8"))
        if m:
            add(m.group(1).strip())

    add(default_qm_kitty_listen_address())
    add(f"unix:{Path(f'/run/user/{os.getuid()}') / KITTY_LISTEN_SOCK_NAME}")
    return order


def norm_hex(s: str) -> str:
    s = (s or "").strip().lstrip("#")
    if len(s) == 6 and re.fullmatch(r"[0-9a-fA-F]{6}", s):
        return s.lower()
    raise ValueError(f"invalid hex colour: {s!r}")


def hx_to_rgb(h: str) -> tuple[int, int, int]:
    h = norm_hex(h)
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def hx(h: str) -> str:
    return "#" + norm_hex(h)


def rgb_csv(h: str) -> str:
    r, g, b = hx_to_rgb(h)
    return f"{r},{g},{b}"


def to_aarrggbb(hex6: str, alpha: int = 255) -> str:
    h = norm_hex(hex6)
    return f"#{alpha:02x}{h}"


def blend_towards(hex6: str, target: str, t: float) -> str:
    a = hx_to_rgb(norm_hex(hex6))
    b = hx_to_rgb(norm_hex(target))
    t = max(0.0, min(1.0, t))
    return norm_hex(
        "".join(f"{int(round(a[i] * (1 - t) + b[i] * t)):02x}" for i in range(3))
    )


def load_colours(path: Path) -> dict[str, str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    c = data.get("colours") or data.get("colors")
    if not isinstance(c, dict):
        print("scheme.json: missing colours object", file=sys.stderr)
        sys.exit(1)
    out = {}
    for k, v in c.items():
        if isinstance(v, str) and v.strip():
            try:
                out[k] = norm_hex(v)
            except ValueError:
                continue
    return out


def hypr_scheme_conf(colours: dict[str, str]) -> str:
    return "".join(f"${name} = {colour}\n" for name, colour in colours.items())


def relative_luminance(hex6: str) -> float:
    def channel(value: int) -> float:
        c = value / 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = hx_to_rgb(hex6)
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast_ratio(fg: str, bg: str) -> float:
    l1 = relative_luminance(fg)
    l2 = relative_luminance(bg)
    lighter, darker = max(l1, l2), min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)


def sort_keys_by_luminance(
    c: dict[str, str], keys: tuple[str, ...], fallback: str, *, reverse: bool = True
) -> tuple[str, ...]:
    return tuple(
        sorted(
            keys,
            key=lambda k: relative_luminance(pick(c, k, fallback)),
            reverse=reverse,
        )
    )


def best_pair(
    c: dict[str, str],
    bg_keys: tuple[str, ...],
    on_keys: tuple[str, ...],
    bg_fallback: str,
    on_fallback: str,
    min_ratio: float = 4.5,
    *,
    lighter_background: bool = False,
) -> tuple[str, str]:
    ordered_bg = (
        sort_keys_by_luminance(c, bg_keys, bg_fallback)
        if lighter_background
        else bg_keys
    )
    bg_key = next((k for k in ordered_bg if c.get(k)), ordered_bg[0])
    bg = pick(c, bg_key, bg_fallback)
    best_on_key = on_keys[0]
    best_on = pick(c, best_on_key, on_fallback)
    best_ratio = contrast_ratio(best_on, bg)
    for on_key in on_keys:
        on = pick(c, on_key, on_fallback)
        ratio = contrast_ratio(on, bg)
        if ratio > best_ratio:
            best_ratio = ratio
            best_on = on
            best_on_key = on_key
    if best_ratio < min_ratio:
        for on_key in ("onSurface", "onPrimary", "onBackground", "inverseSurface"):
            on = pick(c, on_key, on_fallback)
            ratio = contrast_ratio(on, bg)
            if ratio > best_ratio:
                best_ratio = ratio
                best_on = on
                best_on_key = on_key
    return bg_key, best_on_key


def hypr_rgba_var(colour_key: str, alpha: str = "f0") -> str:
    return f"rgba(${colour_key}{alpha})"


def hypr_shadow_tint_hex(colours: dict[str, str]) -> str:
    base = pick(colours, "shadow", "000000")
    tint = pick(colours, "surfaceTint", pick(colours, "primary", "9bd0cc"))
    return blend_towards(base, tint, 0.08)


def hypr_window_glow_vars(colours: dict[str, str]) -> str:
    tint = hypr_shadow_tint_hex(colours)
    border = "primary" if colours.get("primary") else "surfaceTint"
    return f"""$qmShadowTint = {tint}
$shadowColour = rgba($qmShadowTint1a)
$shadowRange = 28
$shadowRenderPower = 2
$activeWindowBorderColour = {hypr_rgba_var(border, "e6")}
$inactiveWindowBorderColour = rgba($onSurfaceVariant11)
"""


def hypr_shadow_decoration_conf() -> str:
    return """decoration {
    shadow {
        range = 28
        render_power = 2
        offset = 0, 8
        color = rgba($qmShadowTint1a)
    }
}
"""


def hypr_groupbar_conf(colours: dict[str, str]) -> str:
    active_bg, active_fg = best_pair(
        colours,
        ("primary", "primaryFixed", "primaryContainer", "primaryDim"),
        ("onPrimaryContainer", "onPrimary", "onPrimaryFixed"),
        "255b58",
        "0d4845",
        lighter_background=True,
    )
    inactive_bg, inactive_fg = best_pair(
        colours,
        (
            "outlineVariant",
            "surfaceBright",
            "surfaceContainerHigh",
            "surfaceVariant",
            "surfaceContainer",
            "surfaceContainerHighest",
        ),
        ("onSurface", "onSurfaceVariant", "onBackground"),
        "1d2827",
        "dce8e6",
        lighter_background=True,
    )
    locked_active_bg, locked_active_fg = best_pair(
        colours,
        ("tertiary", "tertiaryFixed", "tertiaryContainer", "tertiaryDim"),
        ("onTertiaryContainer", "onTertiary", "onTertiaryFixed"),
        "b6e3fe",
        "255369",
        lighter_background=True,
    )
    locked_inactive_bg, locked_inactive_fg = best_pair(
        colours,
        ("secondary", "secondaryFixed", "secondaryContainer", "secondaryDim"),
        ("onSecondaryContainer", "onSecondary", "onSecondaryFixed"),
        "27403e",
        "a9c5c2",
        lighter_background=True,
    )
    return f"""group {{
    groupbar {{
        text_color = rgb(${active_fg})
        text_color_inactive = rgb(${inactive_fg})
        text_color_locked_active = rgb(${locked_active_fg})
        text_color_locked_inactive = rgb(${locked_inactive_fg})

        col.active = {hypr_rgba_var(active_bg, "f5")}
        col.inactive = {hypr_rgba_var(inactive_bg, "f5")}
        col.locked_active = {hypr_rgba_var(locked_active_bg, "f5")}
        col.locked_inactive = {hypr_rgba_var(locked_inactive_bg, "f5")}
    }}
}}
"""


def hypr_theme_overrides_conf(colours: dict[str, str]) -> str:
    return hypr_window_glow_vars(colours) + "\n" + hypr_groupbar_conf(colours)


def _write_hypr_conf(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".conf.tmp")
    tmp.write_text(content, encoding="utf-8")
    tmp.replace(path)
    mirror = Path.home() / ".config" / "hypr" / "scheme" / path.name
    if mirror != path and mirror.parent.exists():
        tmp2 = mirror.with_suffix(".conf.tmp")
        tmp2.write_text(content, encoding="utf-8")
        tmp2.replace(mirror)


def write_hypr_groupbar_conf(colours: dict[str, str]) -> None:
    _write_hypr_conf(HYPR_GROUPBAR_CONF, hypr_theme_overrides_conf(colours))
    _write_hypr_conf(HYPR_SHADOW_CONF, hypr_shadow_decoration_conf())


def sync_hypr_scheme(colours: dict[str, str]) -> None:
    hyprctl = shutil.which("hyprctl")
    if not hyprctl:
        return
    conf = hypr_scheme_conf(colours)
    HYPR_SCHEME_CONF.parent.mkdir(parents=True, exist_ok=True)
    tmp = HYPR_SCHEME_CONF.with_suffix(".conf.tmp")
    tmp.write_text(conf, encoding="utf-8")
    tmp.replace(HYPR_SCHEME_CONF)
    hypr_cfg = Path.home() / ".config" / "hypr" / "scheme" / "current.conf"
    if hypr_cfg != HYPR_SCHEME_CONF and hypr_cfg.parent.exists():
        tmp_cfg = hypr_cfg.with_suffix(".conf.tmp")
        tmp_cfg.write_text(conf, encoding="utf-8")
        tmp_cfg.replace(hypr_cfg)
    write_hypr_groupbar_conf(colours)
    subprocess.run([hyprctl, "reload"], check=False, capture_output=True, timeout=10)


def pick(c: dict[str, str], key: str, fallback: str) -> str:
    v = c.get(key)
    if v:
        return v
    return norm_hex(fallback)


def qt_palette_strings(c: dict[str, str]) -> tuple[str, str, str]:
    ws = pick(c, "onSurface", "dce8e6")
    ws_m = pick(c, "onSurfaceVariant", "a2adac")
    surf = pick(c, "surface", "0a0f0f")
    s_low = pick(c, "surfaceContainerLow", "0e1514")
    s_mid = pick(c, "surfaceContainer", "131b1a")
    s_hi = pick(c, "surfaceContainerHigh", "192120")
    s_max = pick(c, "surfaceContainerHighest", "1d2827")
    out_v = pick(c, "outlineVariant", "3f4a49")
    sh = pick(c, "shadow", "000000")
    pr = pick(c, "primary", "9bd0cc")
    pc = pick(c, "primaryContainer", "255b58")
    on_pc = pick(c, "onPrimaryContainer", "b8ede9")
    ter = pick(c, "tertiary", "b6e3fe")
    light = blend_towards(s_mid, "ffffff", 0.14)
    dark = blend_towards(surf, "000000", 0.22)
    bright = pick(c, "onError", "ffffff")
    ph = pick(c, "onSurfaceVariant", "a2adac")

    def row(
        window_text: str,
        text: str,
        btn_text: str,
        base_bg: str,
        window_bg: str,
        bright_t: str,
    ) -> list[str]:
        return [
            to_aarrggbb(window_text),
            to_aarrggbb(s_hi),
            to_aarrggbb(light),
            to_aarrggbb(s_mid),
            to_aarrggbb(dark),
            to_aarrggbb(out_v),
            to_aarrggbb(text),
            to_aarrggbb(bright_t),
            to_aarrggbb(btn_text),
            to_aarrggbb(base_bg),
            to_aarrggbb(window_bg),
            to_aarrggbb(sh),
            to_aarrggbb(pc),
            to_aarrggbb(on_pc),
            to_aarrggbb(pr),
            to_aarrggbb(ter),
            to_aarrggbb(s_mid),
            to_aarrggbb(ws),
            to_aarrggbb(s_max),
            to_aarrggbb(ws),
            to_aarrggbb(ph, 128),
        ]

    active = row(ws, ws, ws, surf, s_low, bright)
    inactive = row(ws_m, ws_m, ws_m, blend_towards(surf, "000000", 0.06), blend_towards(s_low, "000000", 0.06), bright)
    disabled = row(ws_m, ws_m, ws_m, blend_towards(surf, "ffffff", 0.04), blend_towards(s_low, "ffffff", 0.04), bright)

    def fmt(lst: list[str]) -> str:
        return ", ".join(lst)

    return fmt(active), fmt(inactive), fmt(disabled)


def write_qtct_colors(c: dict[str, str]) -> Path:
    root = Path.home() / ".config" / "qt6ct"
    conf_name = "qt6ct.conf"
    col_dir = root / "colors"
    col_dir.mkdir(parents=True, exist_ok=True)
    path = col_dir / f"{KDE_SCHEME_KEY}.conf"
    a, i, d = qt_palette_strings(c)
    path.write_text(
        "[ColorScheme]\n"
        f"active_colors={a}\n"
        f"inactive_colors={i}\n"
        f"disabled_colors={d}\n",
        encoding="utf-8",
    )
    cfgp = configparser.ConfigParser(interpolation=None)
    cfgp.optionxform = str
    conf = root / conf_name
    cfgp.read(conf, encoding="utf-8")
    if "Appearance" not in cfgp:
        cfgp["Appearance"] = {}
    app = cfgp["Appearance"]
    if not str(app.get("style", "")).strip():
        app["style"] = "Fusion"
    app["custom_palette"] = "true"
    app["color_scheme_path"] = str(path.resolve())
    with conf.open("w", encoding="utf-8") as f:
        cfgp.write(f, space_around_delimiters=False)
    return path


def kitty_conf_from_scheme(c: dict[str, str]) -> str:
    fg = pick(c, "onSurface", "dce8e6")
    bg = pick(c, "surface", "0a0f0f")
    cur = pick(c, "primary", "9bd0cc")
    sel_bg = pick(c, "primaryContainer", "255b58")
    sel_fg = pick(c, "onPrimaryContainer", "b8ede9")
    url = pick(c, "primary", "9bd0cc")
    lines = [
        "# Generated by quantum-moon (Caelestia scheme) — do not edit",
        f"foreground            {hx(fg)}",
        f"background            {hx(bg)}",
        f"selection_foreground  {hx(sel_fg)}",
        f"selection_background  {hx(sel_bg)}",
        f"cursor                  {hx(cur)}",
        f"cursor_text_color       {hx(bg)}",
        f"url_color               {hx(url)}",
    ]
    for n in range(16):
        key = f"term{n}"
        fb = ("000000", "cc0000", "4e9a06", "c4a000", "3465a4", "75507b", "06989a", "d3d7cf",
              "555753", "ef2929", "8ae234", "fce94f", "729fcf", "ad7fa8", "34e2e2", "eeeeec")[n]
        lines.append(f"color{n}                  {hx(pick(c, key, fb))}")
    return "\n".join(lines) + "\n"


def ensure_kitty_include(kitty_dir: Path) -> None:
    kitty_dir.mkdir(parents=True, exist_ok=True)
    dest = kitty_dir / "kitty.conf"
    inc = "include colors-caelestia-qm.conf\n"
    rc = "allow_remote_control socket\n"
    lo = f"listen_on unix:${{XDG_RUNTIME_DIR}}/{KITTY_LISTEN_SOCK_NAME}\n"
    intro = (
        "# quantum-moon: listen_on + allow_remote_control so qm-apply can run\n"
        "# kitten @ --to … set-colors without a controlling TTY.\n"
    )
    if dest.is_file():
        body = dest.read_text(encoding="utf-8")
        prefix = ""
        if "allow_remote_control" not in body.lower():
            prefix += rc
        if LISTEN_ON_RE.search(body) is None:
            prefix += lo
        if "colors-caelestia-qm.conf" not in body:
            prefix += inc
        if prefix:
            dest.write_text(intro + prefix + body, encoding="utf-8")
        return
    dest.write_text(intro + rc + lo + inc, encoding="utf-8")


def refresh_kitty_colors(colors_file: Path) -> bool:
    exe = shutil.which("kitten") or shutil.which("kitty")
    if not exe:
        return False
    kitty_conf = Path.home() / ".config" / "kitty" / "kitty.conf"
    addrs = kitty_rc_candidate_addresses(kitty_conf)
    dbg = os.environ.get("CAELESTIA_QM_DEBUG", "").strip() not in ("", "0", "false", "no")
    last_r: subprocess.CompletedProcess[str] | None = None

    def run_rc(args: list[str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [exe, "@", *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=12,
        )

    for to in addrs:
        last_r = run_rc(
            [
                "--to",
                to,
                "set-colors",
                "--all",
                "--configured",
                str(colors_file),
            ]
        )
        if last_r.returncode == 0:
            return True

    if kitty_conf.is_file():
        kcf = str(kitty_conf.resolve())
        for to in addrs:
            last_r = run_rc(["--to", to, "load-config", kcf])
            if last_r.returncode == 0:
                return True

    if dbg and last_r is not None:
        tail = (last_r.stderr or last_r.stdout or "").strip()
        if tail:
            print(f"quantum-moon: kitty remote control failed: {tail}", file=sys.stderr)
        else:
            first = repr(addrs[0]) if addrs else "none"
            print(
                f"quantum-moon: kitty remote failed (exit {last_r.returncode}, "
                f"tried {len(addrs)} --to address(es); first: {first})",
                file=sys.stderr,
            )
    return False


def kde_colors_ini(c: dict[str, str]) -> str:
    win = pick(c, "surfaceContainerLow", "0e1514")
    win_alt = pick(c, "surfaceContainer", "131b1a")
    view = pick(c, "surface", "0a0f0f")
    view_alt = pick(c, "surfaceContainerLow", "0e1514")
    txt = pick(c, "onSurface", "dce8e6")
    txt_muted = pick(c, "onSurfaceVariant", "a2adac")
    sel_bg = pick(c, "primaryContainer", "255b58")
    sel_fg = pick(c, "onPrimaryContainer", "b8ede9")
    link = pick(c, "primary", "9bd0cc")
    visited = pick(c, "tertiary", "b6e3fe")
    neg = pick(c, "error", "c01c28")
    pos = pick(c, "success", "26a269")
    neu = pick(c, "outline", "6d7876")
    active = pick(c, "secondary", "b0ccc9")
    tip_bg = pick(c, "surfaceContainerHighest", "1d2827")
    tip_fg = pick(c, "onSurface", "dce8e6")
    btn = pick(c, "surfaceContainerHigh", "192120")
    deco = pick(c, "outline", "6d7876")
    wm = pick(c, "surfaceContainerLow", "0e1514")
    wm_in = pick(c, "surfaceContainer", "131b1a")
    wm_txt_dim = pick(c, "onSurfaceVariant", "a2adac")

    def block(
        bg_n: str,
        bg_a: str,
        fg: str,
        fg_in: str,
        fg_link: str,
        fg_vis: str,
    ) -> dict[str, str]:
        return {
            "BackgroundNormal": rgb_csv(bg_n),
            "BackgroundAlternate": rgb_csv(bg_a),
            "DecorationFocus": rgb_csv(deco),
            "DecorationHover": rgb_csv(deco),
            "ForegroundActive": rgb_csv(active),
            "ForegroundInactive": rgb_csv(fg_in),
            "ForegroundLink": rgb_csv(fg_link),
            "ForegroundNegative": rgb_csv(neg),
            "ForegroundNeutral": rgb_csv(neu),
            "ForegroundNormal": rgb_csv(fg),
            "ForegroundPositive": rgb_csv(pos),
            "ForegroundVisited": rgb_csv(fg_vis),
        }

    b_win = block(win, win_alt, txt, txt_muted, link, visited)
    b_view = block(view, view_alt, txt, txt_muted, link, visited)
    b_sel = block(sel_bg, sel_bg, sel_fg, txt_muted, link, visited)
    b_btn = block(btn, btn, txt, txt_muted, link, visited)
    b_tip = block(tip_bg, tip_bg, tip_fg, txt_muted, link, visited)
    b_comp = dict(b_win)
    b_header = block(btn, win, txt, txt_muted, link, visited)
    b_header_inactive = block(win, btn, txt, txt_muted, link, visited)

    def emit_section(title: str, d: dict[str, str]) -> list[str]:
        out = [title]
        out.extend(f"{k}={v}" for k, v in d.items())
        out.append("")
        return out

    lines = [
        "[ColorEffects:Disabled]",
        "Color=112,111,110",
        "ColorAmount=0",
        "ColorEffect=0",
        "ContrastAmount=0.65",
        "ContrastEffect=1",
        "IntensityAmount=0.1",
        "IntensityEffect=2",
        "",
        "[ColorEffects:Inactive]",
        "ChangeSelectionColor=true",
        "Color=112,111,110",
        "ColorAmount=0.025",
        "ColorEffect=2",
        "ContrastAmount=0.1",
        "ContrastEffect=2",
        "Enable=false",
        "IntensityAmount=0",
        "IntensityEffect=0",
        "",
    ]
    for title, d in (
        ("[Colors:Button]", b_btn),
        ("[Colors:Complementary]", b_comp),
        ("[Colors:Header]", b_header),
        ("[Colors:Header][Inactive]", b_header_inactive),
        ("[Colors:Selection]", b_sel),
        ("[Colors:Tooltip]", b_tip),
        ("[Colors:View]", b_view),
        ("[Colors:Window]", b_win),
    ):
        lines.extend(emit_section(title, d))
    lines.extend(
        [
            "[General]",
            f"ColorScheme={KDE_SCHEME_KEY}",
            "Name=Caelestia Quantum Moon",
            "shadeSortColumn=true",
            "",
            "[KDE]",
            "contrast=4",
            "",
            "[WM]",
            f"activeBackground={rgb_csv(wm)}",
            f"activeBlend={rgb_csv(txt)}",
            f"activeForeground={rgb_csv(txt)}",
            f"inactiveBackground={rgb_csv(wm_in)}",
            f"inactiveBlend={rgb_csv(wm_txt_dim)}",
            f"inactiveForeground={rgb_csv(wm_txt_dim)}",
            "",
        ]
    )
    return "\n".join(lines)


def libadwaita_root_block(c: dict[str, str], selector: str = ":root") -> str:
    window_bg = pick(c, "surfaceContainerLow", "0e1514")
    window_fg = pick(c, "onSurface", "dce8e6")
    view_bg = pick(c, "surfaceContainer", "131b1a")
    view_fg = pick(c, "onSurface", "dce8e6")
    header_bg = pick(c, "surfaceContainerHigh", "192120")
    sidebar_bg = pick(c, "surfaceContainerLow", "0e1514")
    sidebar_fg = pick(c, "onSurfaceVariant", "a2adac")
    sidebar_back = pick(c, "surfaceContainerLowest", "000000")
    if sidebar_back == sidebar_bg:
        sidebar_back = pick(c, "surfaceDim", "0a0f0f")
    pop_bg = pick(c, "surfaceContainerHighest", "1d2827")
    card_bg = pick(c, "surfaceContainerHigh", "192120")
    accent_bg = pick(c, "primary", "9bd0cc")
    accent_fg = pick(c, "onPrimary", "0d4845")
    accent_standalone = pick(c, "primaryFixedDim", "a9deda")
    destructive_bg = pick(c, "error", "c01c28")
    destructive_fg = pick(c, "onError", "ffffff")
    success_bg = pick(c, "success", "26a269")
    success_fg = pick(c, "onSuccess", "ffffff")
    err_bg = pick(c, "errorContainer", "871f21")
    err_fg = pick(c, "onErrorContainer", "ff9993")

    def v(name: str, colour: str) -> str:
        return f"  {name}: {hx(colour)};\n"

    parts = [
        f"{selector} {{\n",
        v("--window-bg-color", window_bg),
        v("--window-fg-color", window_fg),
        v("--view-bg-color", view_bg),
        v("--view-fg-color", view_fg),
        v("--headerbar-bg-color", header_bg),
        v("--headerbar-fg-color", window_fg),
        v("--headerbar-border-color", pick(c, "outline", "6d7876")),
        v("--headerbar-backdrop-color", window_bg),
        "  --headerbar-shade-color: rgba(0, 0, 0, 0.36);\n",
        "  --headerbar-darker-shade-color: rgba(0, 0, 0, 0.5);\n",
        v("--sidebar-bg-color", sidebar_bg),
        v("--sidebar-fg-color", sidebar_fg),
        v("--sidebar-backdrop-color", sidebar_back),
        "  --sidebar-border-color: rgba(0, 0, 0, 0.36);\n",
        "  --sidebar-shade-color: rgba(0, 0, 0, 0.25);\n",
        v("--secondary-sidebar-bg-color", view_bg),
        v("--secondary-sidebar-fg-color", view_fg),
        v("--secondary-sidebar-backdrop-color", window_bg),
        "  --secondary-sidebar-border-color: rgba(0, 0, 0, 0.36);\n",
        "  --secondary-sidebar-shade-color: rgba(0, 0, 0, 0.25);\n",
        v("--card-bg-color", card_bg),
        v("--card-fg-color", view_fg),
        "  --card-shade-color: rgba(0, 0, 0, 0.36);\n",
        v("--dialog-bg-color", pop_bg),
        v("--dialog-fg-color", window_fg),
        v("--popover-bg-color", pop_bg),
        v("--popover-fg-color", window_fg),
        "  --popover-shade-color: rgba(0, 0, 0, 0.25);\n",
        v("--accent-bg-color", accent_bg),
        v("--accent-fg-color", accent_fg),
        v("--accent-color", accent_standalone),
        v("--destructive-bg-color", destructive_bg),
        v("--destructive-fg-color", destructive_fg),
        v("--destructive-color", pick(c, "error", "c01c28")),
        v("--success-bg-color", success_bg),
        v("--success-fg-color", success_fg),
        v("--success-color", pick(c, "success", "26a269")),
        "  --warning-bg-color: #cd9309;\n",
        "  --warning-fg-color: rgba(0, 0, 0, 0.8);\n",
        "  --warning-color: #ffc252;\n",
        v("--error-bg-color", err_bg),
        v("--error-fg-color", err_fg),
        v("--error-color", pick(c, "error", "c01c28")),
        v("--thumbnail-bg-color", pick(c, "surfaceContainerHighest", "1d2827")),
        v("--thumbnail-fg-color", view_fg),
        "  --shade-color: rgba(0, 0, 0, 0.25);\n",
        "  --scrollbar-outline-color: rgba(255, 255, 255, 0.35);\n",
        "}\n",
    ]
    return "".join(parts)


def nautilus_surfaces_css(c: dict[str, str]) -> str:
    win = hx(pick(c, "surfaceContainerLow", "0e1514"))
    txt = hx(pick(c, "onSurface", "dce8e6"))
    view = hx(pick(c, "surfaceContainer", "131b1a"))
    side = hx(pick(c, "surfaceContainerLow", "0e1514"))
    side_txt = hx(pick(c, "onSurfaceVariant", "a2adac"))
    head = hx(pick(c, "surfaceContainerHigh", "192120"))
    sel_bg = hx(pick(c, "primaryContainer", "255b58"))
    sel_fg = hx(pick(c, "onPrimaryContainer", "b8ede9"))
    imp = " !important"
    return (
        "/* Nautilus (libadwaita): direct paints + !important (tokens/cache ignore user gtk.css otherwise). */\n"
        "window.nautilus-window,\n"
        ".nautilus-window.background,\n"
        ".nautilus-window.unified {\n"
        f"  background-color: {win}{imp};\n"
        f"  color: {txt}{imp};\n"
        "}\n"
        ".nautilus-window .sidebar-pane,\n"
        ".nautilus-window placessidebar,\n"
        ".nautilus-window placessidebar list,\n"
        ".nautilus-window .navigation-sidebar {\n"
        f"  background-color: {side}{imp};\n"
        f"  color: {side_txt}{imp};\n"
        "}\n"
        ".nautilus-window .nautilus-list-view.view,\n"
        ".nautilus-window .nautilus-grid-view,\n"
        ".nautilus-window scrolledwindow > viewport > widget {\n"
        f"  background-color: {view}{imp};\n"
        f"  color: {txt}{imp};\n"
        "}\n"
        ".nautilus-window headerbar,\n"
        ".nautilus-window headerbar:backdrop {\n"
        f"  background-color: {head}{imp};\n"
        f"  color: {txt}{imp};\n"
        "}\n"
        ".nautilus-window row:selected {\n"
        f"  background-color: {sel_bg}{imp};\n"
        f"  color: {sel_fg}{imp};\n"
        "}\n"
        ".sidebar.navigation-sidebar {\n"
        f"  background-color: {side}{imp};\n"
        f"  color: {side_txt}{imp};\n"
        "}\n"
    )


def gtk4_reorder_imports_first(css: str) -> str:
    lines = css.splitlines()
    imports: list[str] = []
    rest: list[str] = []
    seen: set[str] = set()
    for raw in lines:
        line = raw.strip()
        if line.startswith("@import"):
            if line not in seen:
                seen.add(line)
                imports.append(line)
            continue
        rest.append(raw)
    if not imports:
        return css
    while rest and not rest[0].strip():
        rest.pop(0)
    return "\n".join(imports) + "\n\n" + "\n".join(rest).rstrip() + ("\n" if rest else "")


def rgba(hex6: str, alpha: float) -> str:
    r, g, b = hx_to_rgb(hex6)
    return f"rgba({r}, {g}, {b}, {alpha})"


def gtk3_block(c: dict[str, str]) -> str:
    base = pick(c, "surfaceContainer", "131b1a")
    text = pick(c, "onSurface", "dce8e6")
    sel_bg = pick(c, "primaryContainer", "255b58")
    sel_fg = pick(c, "onPrimaryContainer", "b8ede9")
    return (
        f"@define-color theme_bg_color {hx(base)};\n"
        f"@define-color theme_fg_color {hx(text)};\n"
        f"@define-color theme_base_color {hx(pick(c, 'surface', '0a0f0f'))};\n"
        f"@define-color theme_text_color {hx(text)};\n"
        f"@define-color theme_selected_bg_color {hx(sel_bg)};\n"
        f"@define-color theme_selected_fg_color {hx(sel_fg)};\n"
        f"@define-color insensitive_bg_color {hx(pick(c, 'surfaceContainerLow', '0e1514'))};\n"
        f"@define-color insensitive_fg_color {hx(pick(c, 'onSurfaceVariant', 'a2adac'))};\n"
        f"@define-color insensitive_base_color {hx(pick(c, 'surfaceContainerLow', '0e1514'))};\n"
        f"@define-color insensitive_text_color {hx(pick(c, 'onSurfaceVariant', 'a2adac'))};\n"
        f"@define-color link_color {hx(pick(c, 'primary', '9bd0cc'))};\n"
    )


def gtk4_flatpak_config_dirs() -> list[Path]:
    base = Path.home() / ".var" / "app"
    if not base.is_dir():
        return []
    out: list[Path] = []
    for app_id in ("org.gnome.Nautilus", "org.gnome.Files"):
        if (base / app_id).is_dir():
            out.append(base / app_id / "config" / "gtk-4.0")
    return out


def merge_gtk4_prefer_dark(gtk4_dir: Path, scheme_json: Path) -> None:
    try:
        data = json.loads(scheme_json.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        prefer_dark = True
    else:
        prefer_dark = str(data.get("mode", "dark")).lower() != "light"
    val = "1" if prefer_dark else "0"
    gtk4_dir.mkdir(parents=True, exist_ok=True)
    ini = gtk4_dir / "settings.ini"
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.optionxform = str
    cfg.read(ini, encoding="utf-8")
    if "Settings" not in cfg:
        cfg["Settings"] = {}
    cfg["Settings"]["gtk-application-prefer-dark-theme"] = val
    with ini.open("w", encoding="utf-8") as f:
        cfg.write(f, space_around_delimiters=False)


def sync_gtk4_everywhere(cfg_home: Path, c: dict[str, str], scheme_json: Path) -> None:
    sync_gtk4_user_css(cfg_home / "gtk-4.0", c)
    merge_gtk4_prefer_dark(cfg_home / "gtk-4.0", scheme_json)
    for fd in gtk4_flatpak_config_dirs():
        sync_gtk4_user_css(fd, c)
        merge_gtk4_prefer_dark(fd, scheme_json)
    state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "quantum-moon"
    state.mkdir(parents=True, exist_ok=True)
    lines = [
        datetime.datetime.now().isoformat(timespec="seconds"),
        f"host_gtk4={cfg_home / 'gtk-4.0' / 'gtk.css'}",
    ]
    for fd in gtk4_flatpak_config_dirs():
        lines.append(f"flatpak_gtk4={fd / 'gtk.css'}")
    (state / "last-gtk-sync.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def strip_gtk4_managed_blocks(css: str) -> str:
    while True:
        m = GTK4_USER_BLOCK_RE.search(css)
        if not m:
            return css
        css = css[: m.start()] + css[m.end() :]


def strip_gtk4_legacy_import(css: str) -> str:
    prev = None
    while prev != css:
        prev = css
        css = GTK4_LEGACY_IMPORT.sub("", css)
    return css


def gtk4_define_color_block(c: dict[str, str]) -> str:
    pr = pick(c, "primary", "9bd0cc")
    on_pr = pick(c, "onPrimary", "0d4845")
    win_bg = pick(c, "surfaceContainerLow", "0e1514")
    win_fg = pick(c, "onSurface", "dce8e6")
    hdr_bg = pick(c, "surfaceContainerHigh", "192120")
    pop_bg = pick(c, "surfaceContainerHighest", "1d2827")
    view_bg = pick(c, "surfaceContainer", "131b1a")
    card_bg = pick(c, "surfaceContainerHigh", "192120")
    side_bg = pick(c, "surfaceContainerLow", "0e1514")
    side_fg = pick(c, "onSurfaceVariant", "a2adac")
    ol = pick(c, "outline", "6d7876")
    side_back = pick(c, "surfaceDim", "0a0f0f")
    sel_bg = pick(c, "primaryContainer", "255b58")
    sel_fg = pick(c, "onPrimaryContainer", "b8ede9")
    lines = [
        f"@define-color accent_color {hx(pr)};",
        f"@define-color accent_fg_color {hx(on_pr)};",
        f"@define-color accent_bg_color {hx(pr)};",
        f"@define-color window_bg_color {hx(win_bg)};",
        f"@define-color window_fg_color {hx(win_fg)};",
        f"@define-color headerbar_bg_color {hx(hdr_bg)};",
        f"@define-color headerbar_fg_color {hx(win_fg)};",
        f"@define-color popover_bg_color {hx(pop_bg)};",
        f"@define-color popover_fg_color {hx(win_fg)};",
        f"@define-color view_bg_color {hx(view_bg)};",
        f"@define-color view_fg_color {hx(win_fg)};",
        f"@define-color card_bg_color {hx(card_bg)};",
        f"@define-color card_fg_color {hx(win_fg)};",
        f"@define-color sidebar_bg_color {hx(side_bg)};",
        f"@define-color sidebar_fg_color {hx(side_fg)};",
        f"@define-color sidebar_border_color {hx(ol)};",
        f"@define-color sidebar_backdrop_color {hx(side_back)};",
        f"@define-color theme_selected_bg_color {hx(sel_bg)};",
        f"@define-color theme_selected_fg_color {hx(sel_fg)};",
    ]
    return "\n".join(lines)


def sync_gtk4_user_css(gtk4_dir: Path, c: dict[str, str]) -> None:
    gtk4_dir.mkdir(parents=True, exist_ok=True)
    path = gtk4_dir / "gtk.css"
    body = path.read_text(encoding="utf-8") if path.is_file() else ""
    body = strip_gtk4_managed_blocks(body)
    body = strip_gtk4_legacy_import(body)
    body = gtk4_reorder_imports_first(body)
    block = (
        f"{GTK4_BLOCK_BEGIN}\n"
        f"{gtk4_define_color_block(c)}\n"
        f"{libadwaita_root_block(c, ':root')}"
        f"{nautilus_surfaces_css(c)}"
        f"{GTK4_BLOCK_END}\n"
    )
    path.write_text(body.rstrip() + "\n\n" + block, encoding="utf-8")


def ensure_gtk3_import(gtk3_dir: Path) -> None:
    gtk3_dir.mkdir(parents=True, exist_ok=True)
    dest = gtk3_dir / "gtk.css"
    marker = "quantum-moon: gtk3 sync"
    if dest.is_file():
        body = dest.read_text(encoding="utf-8")
        if marker in body or "qm-gtk3.css" in body:
            return
        dest.write_text(GTK3_IMPORT_LINE + body, encoding="utf-8")
    else:
        dest.write_text(GTK3_IMPORT_LINE, encoding="utf-8")


def set_kde_color_scheme(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    cfg_dir = path.parent
    fname = path.name
    for bin_name in ("kwriteconfig6", "kwriteconfig5"):
        exe = shutil.which(bin_name)
        if exe:
            subprocess.run(
                [
                    exe,
                    "--file",
                    fname,
                    "--group",
                    "General",
                    "--key",
                    "ColorScheme",
                    KDE_SCHEME_KEY,
                ],
                check=False,
                capture_output=True,
                timeout=5,
                cwd=str(cfg_dir),
            )
            return
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.optionxform = str
    cfg.read(path, encoding="utf-8")
    if "General" not in cfg:
        cfg["General"] = {}
    cfg["General"]["ColorScheme"] = KDE_SCHEME_KEY
    with path.open("w", encoding="utf-8") as f:
        cfg.write(f, space_around_delimiters=False)


def _busctl_filemanager1_property(prop: str) -> dict | None:
    busctl = shutil.which("busctl")
    if not busctl:
        return None
    r = subprocess.run(
        [
            busctl,
            "--json=short",
            "--user",
            "get-property",
            "org.freedesktop.FileManager1",
            "/org/freedesktop/FileManager1",
            "org.freedesktop.FileManager1",
            prop,
        ],
        capture_output=True,
        text=True,
        timeout=8,
    )
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError:
        return None


def _hypr_clients() -> list[dict] | None:
    hyprctl = shutil.which("hyprctl")
    if not hyprctl:
        return None
    try:
        r = subprocess.run(
            [hyprctl, "clients", "-j"],
            capture_output=True,
            text=True,
            timeout=6,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    try:
        data = json.loads(r.stdout)
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, list) else None


def _is_nautilus_client(c: dict) -> bool:
    if not isinstance(c, dict) or not c.get("mapped") or c.get("hidden"):
        return False
    cls = (c.get("class") or "").lower()
    icls = (c.get("initialClass") or "").lower()
    return "nautilus" in cls or "nautilus" in icls


def _addresses_matching(clients: list[dict], match) -> set[str]:
    out: set[str] = set()
    for c in clients:
        if not match(c):
            continue
        addr = c.get("address")
        if addr:
            out.add(str(addr))
    return out


def _geom_from_client(c: dict) -> dict:
    at = c.get("at") or [0, 0]
    sz = c.get("size") or [0, 0]
    ws = c.get("workspace") if isinstance(c.get("workspace"), dict) else {}
    return {
        "at": [int(at[0]), int(at[1])],
        "size": [int(sz[0]), int(sz[1])],
        "workspace_id": ws.get("id"),
        "workspace_name": ws.get("name"),
        "floating": bool(c.get("floating")),
        "pinned": bool(c.get("pinned")),
    }


def _file_uri_path(uri: str) -> str | None:
    if not isinstance(uri, str) or not uri.startswith("file://"):
        return None
    p = urlparse(uri)
    if not p.path:
        return None
    return os.path.normpath(unquote(p.path))


def _title_path_score(title: str, path: str | None) -> int:
    if not path:
        return 0
    t = (title or "").lower()
    pl = path.lower()
    bn = os.path.basename(pl.rstrip(os.sep)).lower()
    score = 0
    if pl and pl in t:
        score += 2000 + min(len(pl), 500)
    if bn and bn in t:
        score += 500 + min(len(bn), 200)
    for part in reversed(pl.split(os.sep)):
        p2 = part.lower()
        if len(p2) >= 2 and p2 in t:
            score += 50
            break
    return score


def _assign_geometry_to_windows(
    windows: list[list[str]], clients: list[dict]
) -> list[dict | None]:
    nclients = [c for c in clients if _is_nautilus_client(c)]
    nclients.sort(
        key=lambda c: (
            (c.get("workspace") or {}).get("id") if isinstance(c.get("workspace"), dict) else 0,
            (c.get("at") or [0, 0])[1],
            (c.get("at") or [0, 0])[0],
            str(c.get("address") or ""),
        )
    )
    used: set[str] = set()
    out: list[dict | None] = []
    for uris in windows:
        path = None
        for u in uris:
            path = _file_uri_path(u)
            if path:
                break
        best_addr: str | None = None
        best_score = -1
        for c in nclients:
            addr = c.get("address")
            if not addr:
                continue
            sa = str(addr)
            if sa in used:
                continue
            title = str(c.get("title") or "")
            sc = _title_path_score(title, path)
            if sc > best_score:
                best_score = sc
                best_addr = str(addr)
        if best_addr is not None and best_score > 0:
            used.add(best_addr)
            c = next(x for x in nclients if str(x.get("address")) == best_addr)
            out.append(_geom_from_client(c))
            continue
        picked: dict | None = None
        for c in nclients:
            addr = c.get("address")
            if not addr:
                continue
            sa = str(addr)
            if sa not in used:
                used.add(sa)
                picked = _geom_from_client(c)
                break
        out.append(picked)
    return out[: len(windows)]


def _hypr_dispatch(arg: str) -> None:
    hyprctl = shutil.which("hyprctl")
    if not hyprctl:
        return
    subprocess.run(
        [hyprctl, "dispatch", arg],
        check=False,
        capture_output=True,
        text=True,
        timeout=5,
    )


def _workspace_moveto_arg(g: dict) -> str | None:
    wid = g.get("workspace_id")
    name = g.get("workspace_name")
    if isinstance(name, str) and name.startswith("special:"):
        return name
    if wid is None:
        return None
    if isinstance(wid, str):
        s = wid.strip()
        if s.startswith("name:") or s.startswith("special:"):
            return s
        return f"name:{s}"
    if isinstance(wid, int) and wid < 0 and isinstance(name, str):
        return name
    return str(wid)


def _restore_client_hypr(address: str, g: dict) -> None:
    warg = _workspace_moveto_arg(g)
    if warg is not None:
        _hypr_dispatch(f"movetoworkspacesilent {warg},address:{address}")
    x, y = g["at"]
    w, h = g["size"]
    if g.get("floating"):
        _hypr_dispatch(f"setfloating,address:{address}")
        _hypr_dispatch(f"resizewindowpixel exact {w} {h},address:{address}")
        _hypr_dispatch(f"movewindowpixel exact {x} {y},address:{address}")
    else:
        _hypr_dispatch(f"settiled,address:{address}")
    if g.get("pinned") and g.get("floating"):
        _hypr_dispatch(f"pin,address:{address}")


def _pick_new_address_by_pid(clients: list[dict], diff: set[str]) -> str:
    best: str | None = None
    best_pid = -1
    for c in clients:
        addr = c.get("address")
        if not addr:
            continue
        sa = str(addr)
        if sa not in diff:
            continue
        try:
            pid = int(c.get("pid") or 0)
        except (TypeError, ValueError):
            pid = 0
        if pid >= best_pid:
            best_pid = pid
            best = sa
    return best if best is not None else sorted(diff)[0]


def _wait_new_client_address(
    prev: set[str],
    want_total: int,
    match,
    timeout: float = 5.0,
) -> str | None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        clients = _hypr_clients()
        if not clients:
            time.sleep(0.05)
            continue
        curr = _addresses_matching(clients, match)
        if len(curr) >= want_total:
            diff = curr - prev
            if diff:
                if len(diff) == 1:
                    return next(iter(diff))
                return _pick_new_address_by_pid(clients, diff)
        time.sleep(0.05)
    return None


def collect_open_nautilus_window_uris() -> list[list[str]]:
    j = _busctl_filemanager1_property("OpenWindowsWithLocations")
    if not j or not isinstance(j.get("data"), dict):
        return []
    data: dict = j["data"]
    if data:
        out: list[list[str]] = []
        for uris in data.values():
            if isinstance(uris, list) and uris:
                row = [str(x) for x in uris if isinstance(x, str) and x]
                if row:
                    out.append(row)
        return out
    j2 = _busctl_filemanager1_property("OpenLocations")
    if j2 and isinstance(j2.get("data"), list):
        locs = [str(x) for x in j2["data"] if isinstance(x, str) and x]
        if locs:
            return [locs]
    return []


def _flatpak_nautilus_app_id() -> str | None:
    if not shutil.which("flatpak"):
        return None
    r = subprocess.run(
        ["flatpak", "list", "--app", "--columns=application"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if r.returncode != 0:
        return None
    apps = {ln.strip() for ln in r.stdout.splitlines() if ln.strip()}
    if "org.gnome.Nautilus" in apps:
        return "org.gnome.Nautilus"
    if "org.gnome.Files" in apps:
        return "org.gnome.Files"
    return None


def kitty_sigusr1_reload_pids() -> list[int]:
    pids = _kitty_pids()
    if not pids:
        return []
    mains: dict[int, None] = {}
    listeners: dict[int, None] = {}
    for pid in pids:
        try:
            env = _read_proc_environ(pid)
        except OSError:
            continue
        if env.get("KITTY_LISTEN_ON"):
            listeners[pid] = None
        kp = env.get("KITTY_PID")
        if kp and str(kp).isdigit():
            mains[int(kp)] = None
    if mains:
        return list(mains.keys())
    if listeners:
        return list(listeners.keys())
    return [min(pids)]


def signal_kitty_reload_config() -> None:
    sig = getattr(signal, "SIGUSR1", None)
    if sig is None:
        return
    for pid in kitty_sigusr1_reload_pids():
        try:
            os.kill(pid, sig)
        except (ProcessLookupError, PermissionError, OSError):
            pass


def reload_kitty_terminals(colors_file: Path) -> None:
    refresh_kitty_colors(colors_file)
    signal_kitty_reload_config()


def _wait_no_nautilus_process(timeout: float = 4.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        r = subprocess.run(
            ["pgrep", "-x", "nautilus"],
            capture_output=True,
            timeout=2,
        )
        if r.returncode != 0:
            return
        time.sleep(0.06)


def _spawn_nautilus_uris(uris: list[str], new_window: bool) -> None:
    if not uris:
        return
    env = os.environ.copy()
    env["GTK_DEBUG"] = "no-css-cache"
    devnull = subprocess.DEVNULL
    nautilus_bin = shutil.which("nautilus")
    if nautilus_bin:
        cmd = [nautilus_bin]
        if new_window:
            cmd.append("--new-window")
        cmd.extend(uris)
        subprocess.Popen(
            cmd,
            env=env,
            stdin=devnull,
            stdout=devnull,
            stderr=devnull,
            start_new_session=True,
        )
        return
    app = _flatpak_nautilus_app_id()
    if not app:
        return
    cmd = [
        "flatpak",
        "run",
        "--env=GTK_DEBUG=no-css-cache",
        app,
        "--",
    ]
    if new_window:
        cmd.append("--new-window")
    cmd.extend(uris)
    subprocess.Popen(
        cmd,
        stdin=devnull,
        stdout=devnull,
        stderr=devnull,
        start_new_session=True,
    )


def stop_nautilus_for_theme_reload() -> None:
    windows = collect_open_nautilus_window_uris()
    geoms: list[dict | None] | None = None
    if windows:
        clients_before = _hypr_clients()
        if clients_before is not None:
            geoms = _assign_geometry_to_windows(windows, clients_before)
    if shutil.which("flatpak"):
        for app in ("org.gnome.Nautilus", "org.gnome.Files"):
            subprocess.run(
                ["flatpak", "kill", app],
                check=False,
                capture_output=True,
                timeout=15,
            )
    if shutil.which("pkill"):
        subprocess.run(
            ["pkill", "-TERM", "-x", "nautilus"],
            check=False,
            capture_output=True,
            timeout=10,
        )
    if not windows:
        return
    _wait_no_nautilus_process()
    use_hypr_restore = bool(
        geoms
        and shutil.which("hyprctl")
        and any(g is not None for g in geoms)
    )
    if use_hypr_restore:
        prev: set[str] = set()
        for i, uris in enumerate(windows):
            _spawn_nautilus_uris(uris, new_window=(i > 0))
            addr = _wait_new_client_address(prev, len(prev) + 1, _is_nautilus_client)
            if addr and i < len(geoms) and geoms[i]:
                _restore_client_hypr(addr, geoms[i])
            if addr:
                prev.add(addr)
    else:
        for i, uris in enumerate(windows):
            _spawn_nautilus_uris(uris, new_window=(i > 0))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("scheme_json", nargs="?", type=Path, default=SCHEME_FILE)
    args = ap.parse_args()
    path: Path = args.scheme_json
    if not path.is_file():
        print(f"missing {path}", file=sys.stderr)
        sys.exit(0)

    c = load_colours(path)

    kde_dir = Path.home() / ".local" / "share" / "color-schemes"
    kde_dir.mkdir(parents=True, exist_ok=True)
    (kde_dir / KDE_SCHEME_FILE).write_text(kde_colors_ini(c), encoding="utf-8")

    GENERATED_CSS.parent.mkdir(parents=True, exist_ok=True)
    GENERATED_CSS.write_text(
        "/* Generated by quantum-moon qm-sync-file-manager-theme — do not edit */\n"
        + libadwaita_root_block(c)
        + nautilus_surfaces_css(c),
        encoding="utf-8",
    )

    gtk3_path = GENERATED_CSS.parent / "qm-gtk3.css"
    gtk3_path.write_text(
        "/* Generated by quantum-moon — GTK3 companion */\n" + gtk3_block(c),
        encoding="utf-8",
    )

    cfg_home = Path.home() / ".config"
    sync_gtk4_everywhere(cfg_home, c, path)
    ensure_gtk3_import(cfg_home / "gtk-3.0")

    set_kde_color_scheme(cfg_home / "kdeglobals")

    kdir = cfg_home / "kitty"
    kitty_colors = kdir / "colors-caelestia-qm.conf"
    kitty_colors.write_text(kitty_conf_from_scheme(c), encoding="utf-8")
    ensure_kitty_include(kdir)
    reload_kitty_terminals(kitty_colors)

    write_qtct_colors(c)

    for cmd in (
        ["plasma-apply-colorscheme", KDE_SCHEME_KEY],
        ["kapplycolorscheme", KDE_SCHEME_KEY],
    ):
        if shutil.which(cmd[0]):
            subprocess.run(cmd, check=False, capture_output=True, timeout=5)

    stop_nautilus_for_theme_reload()
    sync_hypr_scheme(c)


if __name__ == "__main__":
    main()
