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
  local pf sock
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
