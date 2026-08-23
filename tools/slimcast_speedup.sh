#!/usr/bin/env bash
# Speed up the Cursor / Slimcast (AnyOS) remote desktop and drop unused caches.
# Safe to re-run. Does not stop VNC, XFCE, or Cursor.
set -u -o pipefail

DISPLAY="${DISPLAY:-:1}"
export DISPLAY

bytes_of() {
  du -sb "$1" 2>/dev/null | awk '{print $1}'
}

human() {
  local n="${1:-0}"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "$n" 2>/dev/null || echo "${n}B"
  else
    echo "${n}B"
  fi
}

load_session_env() {
  local pid
  for pid in $(pgrep -n xfconfd 2>/dev/null) $(pgrep -n xfce4-session 2>/dev/null); do
    [[ -r "/proc/${pid}/environ" ]] || continue
    while IFS= read -r -d '' line; do
      case "$line" in
        DBUS_SESSION_BUS_ADDRESS=*|XDG_RUNTIME_DIR=*) export "$line" ;;
      esac
    done < "/proc/${pid}/environ"
    return 0
  done
  return 0
}

xfset() {
  local channel="$1" prop="$2" type="$3" value="$4"
  command -v xfconf-query >/dev/null 2>&1 || return 0
  xfconf-query -c "$channel" -p "$prop" -n -t "$type" -s "$value" >/dev/null 2>&1 || true
}

stop_plank() {
  local plank_pid ppid cmd runner_pid
  plank_pid="$(pgrep -x plank | head -n 1 || true)"
  if [[ -n "$plank_pid" ]]; then
    ppid="$(ps -o ppid= -p "$plank_pid" 2>/dev/null | tr -d ' ')"
    cmd="$(ps -o cmd= -p "$ppid" 2>/dev/null || true)"
    # desktop-init.sh respawns Plank from a subshell. Kill that subshell, not the keep-alive parent.
    if [[ "$cmd" == *desktop-init.sh* ]]; then
      kill "$ppid" 2>/dev/null || true
    fi
    kill "$plank_pid" 2>/dev/null || true
  fi
  pgrep -x bamfdaemon >/dev/null 2>&1 && kill $(pgrep -x bamfdaemon) 2>/dev/null || true
  while IFS= read -r runner_pid; do
    [[ -z "$runner_pid" || "$runner_pid" == "$$" ]] && continue
    kill "$runner_pid" 2>/dev/null || true
  done < <(pgrep -f '/usr/lib/.*/bamf/bamfdaemon-dbus-runner' || true)
}

purge_dir() {
  local path="$1"
  local before after
  [[ -e "$path" ]] || return 0
  before="$(bytes_of "$path")"
  rm -rf "$path" && echo "Removed $(human "${before:-0}"): $path" || echo "Could not remove: $path"
}

tune_desktop() {
  command -v xfconf-query >/dev/null 2>&1 || return 0
  load_session_env

  xfset xfwm4 /general/use_compositing bool false
  xfset xfwm4 /general/cycle_preview bool false
  xfset xfwm4 /general/zoom_desktop bool false
  xfset xfwm4 /general/show_frame_shadow bool false
  xfset xfwm4 /general/show_popup_shadow bool false
  xfset xfwm4 /general/workspace_count int 1
  xfset xfwm4 /general/vblank_mode string off
  xfset xfwm4 /general/unredirect_overlays bool true

  # image-style 0 = solid color, no wallpaper decode over VNC
  local path
  for path in \
    /backdrop/screen0/monitorscreen/workspace0/image-style \
    /backdrop/screen0/monitor0/workspace0/image-style \
    /backdrop/screen0/monitorVNC-0/workspace0/image-style \
    /backdrop/screen0/monitorVNC-0/workspace1/image-style \
    /backdrop/screen0/monitorVNC-0/workspace2/image-style \
    /backdrop/screen0/monitorVNC-0/workspace3/image-style
  do
    xfset xfce4-desktop "$path" int 0
  done
}

clean_caches() {
  purge_dir "${HOME}/.cache/go-build"
  purge_dir "${HOME}/.cache/thumbnails"
  purge_dir "${HOME}/.cache/mesa_shader_cache"
  purge_dir "${HOME}/.cache/mesa_shader_cache_db"
  purge_dir "${HOME}/.cache/fontconfig"
  purge_dir "${HOME}/.nvm/.cache"
  purge_dir "${HOME}/go/pkg/mod/cache"
  purge_dir "${HOME}/.local/share/Trash"
  purge_dir /tmp/node-compile-cache
  rm -f /tmp/core.* 2>/dev/null || true
}

print_status() {
  echo
  echo "Desktop compositor: $(xfconf-query -c xfwm4 -p /general/use_compositing 2>/dev/null || echo n/a)"
  echo -n "Plank: "
  pgrep -x plank >/dev/null 2>&1 && echo running || echo stopped
  echo "Load: $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || true)"
  df -h / | tail -n 1
  free -h | awk 'NR==1 || NR==2'
}

main() {
  echo "=============================="
  echo " Slimcast desktop speedup"
  echo "=============================="
  echo
  echo "Turning off compositor, wallpaper, and Plank."
  echo "Clearing leftover caches and temp files."
  echo

  tune_desktop
  stop_plank
  clean_caches
  print_status
  echo
  echo "Done. VNC was left running so the remote desktop stays connected."
}

main "$@"
