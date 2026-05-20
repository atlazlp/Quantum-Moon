# Shared helpers for quantum-moon video wallpaper (sourced by other scripts).

SCRIPT_DIR_LIB="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]:-$0}")")" && pwd)"
QM_ROOT="$(cd "${SCRIPT_DIR_LIB}/.." && pwd)"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/quantum-moon"
MODES_DIR="${QM_ROOT}/modes"

qm_video_sock() {
  printf '%s' "${XDG_RUNTIME_DIR:-/tmp}/quantum-moon-mpvpaper.sock"
}

qm_video_pidfile() {
  printf '%s' "${STATE_DIR}/mpvpaper.pid"
}

qm_repo_root() {
  cd "${QM_ROOT}/.." && pwd
}

qm_is_lfs_pointer() {
  local f="$1"
  [[ -f "${f}" ]] || return 1
  head -c 256 "${f}" 2>/dev/null | grep -q 'git-lfs.github.com'
}

qm_video_file_usable() {
  local f="$1"
  [[ -f "${f}" ]] || return 1
  if qm_is_lfs_pointer "${f}"; then
    return 1
  fi
  if file -b "${f}" 2>/dev/null | grep -qiE 'ISO Media|Matroska|WebM|AVI |video'; then
    return 0
  fi
  local sz
  sz="$(stat -c%s "${f}" 2>/dev/null || echo 0)"
  [[ "${sz}" -gt 1048576 ]]
}

qm_lfs_pull_center_videos() {
  local repo
  repo="$(qm_repo_root)"
  [[ -d "${repo}/.git" ]] || return 1
  command -v git-lfs >/dev/null 2>&1 || return 1
  (cd "${repo}" && git lfs pull --include='quantum-moon/modes/*/wallpapers/center.mp4')
}

qm_ensure_center_video_file() {
  local vid="$1"
  if qm_video_file_usable "${vid}"; then
    return 0
  fi
  if qm_is_lfs_pointer "${vid}"; then
    echo "quantum-moon: center.mp4 is a Git LFS pointer; pulling real videos…" >&2
    qm_lfs_pull_center_videos || true
  fi
  qm_video_file_usable "${vid}"
}

qm_mpvpaper_running() {
  local pf pid comm
  pf="$(qm_video_pidfile)"
  [[ -f "${pf}" ]] || return 1
  pid="$(tr -d '[:space:]' <"${pf}")"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" 2>/dev/null || return 1
  comm="$(ps -p "${pid}" -o comm= 2>/dev/null || true)"
  [[ "${comm}" == *mpvpaper* ]]
}

qm_current_slug() {
  local state="${STATE_DIR}/current.json"
  [[ -f "${state}" ]] || return 1
  jq -r '.slug // empty' "${state}" 2>/dev/null
}

qm_sorted_monitors_json() {
  hyprctl monitors -j 2>/dev/null | jq -c 'sort_by(.x, .y)' || echo '[]'
}

qm_center_slot_index() {
  local sorted count idx
  sorted="$(qm_sorted_monitors_json)"
  count="$(echo "${sorted}" | jq 'length // 0')"
  idx=0
  if [[ "${count}" =~ ^[0-9]+$ ]] && [[ "${count}" -ge 2 ]]; then
    idx=1
  fi
  echo "${idx}"
}

qm_center_monitor_name() {
  local sorted idx
  sorted="$(qm_sorted_monitors_json)"
  idx="$(qm_center_slot_index)"
  echo "${sorted}" | jq -r ".[${idx}] | .name // empty"
}

qm_center_monitor_id() {
  local sorted idx
  sorted="$(qm_sorted_monitors_json)"
  idx="$(qm_center_slot_index)"
  echo "${sorted}" | jq -r ".[${idx}] | .id // empty"
}

qm_center_active_workspace_id() {
  local sorted idx
  sorted="$(qm_sorted_monitors_json)"
  idx="$(qm_center_slot_index)"
  echo "${sorted}" | jq -r ".[${idx}] | .activeWorkspace.id // empty"
}

qm_video_stop() {
  mkdir -p "${STATE_DIR}"
  local pf sock center_mon
  pf="$(qm_video_pidfile)"
  sock="$(qm_video_sock)"
  if [[ -f "${pf}" ]]; then
    local pid
    pid="$(cat "${pf}" 2>/dev/null)" || true
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
      for _ in $(seq 1 40); do
        kill -0 "${pid}" 2>/dev/null || break
        sleep 0.05
      done
      kill -9 "${pid}" 2>/dev/null || true
    fi
    rm -f "${pf}"
  fi
  center_mon="$(qm_center_monitor_name 2>/dev/null || true)"
  if [[ -n "${center_mon}" ]]; then
    pkill -f "mpvpaper.*[[:space:]]${center_mon}[[:space:]]" 2>/dev/null || true
  fi
  if pgrep -x mpvpaper >/dev/null 2>&1; then
    pkill -x mpvpaper 2>/dev/null || true
    for _ in $(seq 1 30); do
      pgrep -x mpvpaper >/dev/null 2>&1 || break
      sleep 0.05
    done
    pkill -9 -x mpvpaper 2>/dev/null || true
  fi
  rm -f "${sock}"
}

qm_mpv_set_pause() {
  local sock="$1" want="$2"
  [[ -S "${sock}" ]] || return 1
  python3 -c '
import json, socket, sys
sock, want = sys.argv[1], sys.argv[2] == "true"
msg = json.dumps({"command": ["set_property", "pause", want]}) + "\n"
s = socket.socket(socket.AF_UNIX)
s.connect(sock)
s.sendall(msg.encode())
s.close()
' "${sock}" "${want}"
}

qm_count_toplevels_on_center_workspace() {
  local ws mid clients
  ws="$(qm_center_active_workspace_id)"
  mid="$(qm_center_monitor_id)"
  [[ -n "${ws}" && "${ws}" != "null" ]] || { echo 0; return 0; }
  [[ -n "${mid}" && "${mid}" != "null" ]] || { echo 0; return 0; }

  if ! clients="$(hyprctl clients -j 2>/dev/null)"; then
    echo 0
    return 0
  fi

  echo "${clients}" | jq --argjson ws "${ws}" --argjson mid "${mid}" '
    [.[] | select(
      (.address != null) and
      (.workspace.id == $ws) and
      (.monitor == $mid) and
      (.mapped != false) and
      (.hidden != true)
    )] | length
  '
}

qm_desktop_visible_on_center() {
  local n
  n="$(qm_count_toplevels_on_center_workspace)"
  [[ "${n}" == "0" ]]
}
