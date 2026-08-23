#!/usr/bin/env bash
# Speed up the Cursor / Slimcast (AnyOS) remote desktop and drop unused caches.
# Safe to re-run. Restarts VNC only when frame rate/depth are still at the
# default 1920x1200 @ 60fps values that make the remote desktop unusable.
set -u -o pipefail

DISPLAY="${DISPLAY:-:1}"
export DISPLAY

TARGET_GEOM="1024x768"
TARGET_DEPTH="16"
TARGET_FPS="8"
VNC_PORT="${VNC_PORT:-5901}"
VNC_XSTARTUP="${VNC_XSTARTUP:-/tmp/anyos-xstartup}"
VNC_CONFIG="${HOME}/.vnc/config"

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

current_geom() {
  xdpyinfo 2>/dev/null | awk '/dimensions:/{print $2; exit}'
}

current_depth() {
  xdpyinfo 2>/dev/null | awk '/depth of root window:/{print $5; exit}'
}

current_fps() {
  vncconfig -get FrameRate 2>/dev/null || echo ""
}

write_vnc_config() {
  mkdir -p "${HOME}/.vnc"
  cat > "$VNC_CONFIG" <<EOF
geometry=${TARGET_GEOM}
depth=${TARGET_DEPTH}
FrameRate=${TARGET_FPS}
CompareFB=2
ImprovedHextile=1
ZlibLevel=2
AcceptSetDesktopSize=0
EOF
}

vnc_needs_restart() {
  local fps depth
  fps="$(current_fps)"
  depth="$(current_depth)"
  [[ "$fps" != "$TARGET_FPS" || "$depth" != "$TARGET_DEPTH" ]]
}

restart_vnc() {
  command -v tigervncserver >/dev/null 2>&1 || return 1
  [[ -x "$VNC_XSTARTUP" ]] || return 1

  echo "Restarting VNC at ${TARGET_GEOM} depth ${TARGET_DEPTH} ${TARGET_FPS}fps..."
  tigervncserver -kill "${DISPLAY}" >/dev/null 2>&1 || true
  sleep 1
  if pgrep -x Xtigervnc >/dev/null 2>&1; then
    xargs -r kill -9 < <(pgrep -x Xtigervnc) 2>/dev/null || true
    sleep 1
  fi

  tigervncserver "${DISPLAY}" \
    -geometry "$TARGET_GEOM" \
    -depth "$TARGET_DEPTH" \
    -rfbport "$VNC_PORT" \
    -dpi 96 \
    -localhost \
    -desktop AnyOS \
    -SecurityTypes None \
    -xstartup "$VNC_XSTARTUP" \
    -FrameRate "$TARGET_FPS" \
    -AcceptSetDesktopSize=0 \
    -CompareFB 2 \
    -ZlibLevel 2 \
    -ImprovedHextile=1

  local i
  for i in $(seq 1 40); do
    if xdpyinfo >/dev/null 2>&1; then
      echo "VNC is back."
      return 0
    fi
    sleep 0.25
  done
  echo "WARNING: VNC did not come back in time."
  return 1
}

shrink_display() {
  command -v xrandr >/dev/null 2>&1 || return 0
  local output
  output="$(xrandr 2>/dev/null | awk '/ connected/{print $1; exit}')"
  [[ -n "$output" ]] || return 0
  if [[ "$(current_geom)" == "${TARGET_GEOM}" ]]; then
    return 0
  fi
  xrandr --output "$output" --mode "$TARGET_GEOM" 2>/dev/null \
    || xrandr --output "$output" --mode 1024x768 2>/dev/null \
    || true
}

stop_plank() {
  local plank_pid ppid cmd runner_pid
  plank_pid="$(pgrep -x plank | head -n 1 || true)"
  if [[ -n "$plank_pid" ]]; then
    ppid="$(ps -o ppid= -p "$plank_pid" 2>/dev/null | tr -d ' ')"
    cmd="$(ps -o cmd= -p "$ppid" 2>/dev/null || true)"
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

stop_xfdesktop() {
  if pgrep -x xfdesktop >/dev/null 2>&1; then
    xfdesktop --quit >/dev/null 2>&1 || kill $(pgrep -x xfdesktop) 2>/dev/null || true
  fi
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

  xset s off >/dev/null 2>&1 || true
  xset -dpms >/dev/null 2>&1 || true
}

purge_dir() {
  local path="$1"
  local before
  [[ -e "$path" ]] || return 0
  before="$(bytes_of "$path")"
  rm -rf "$path" && echo "Removed $(human "${before:-0}"): $path" || echo "Could not remove: $path"
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
  echo "Geometry: $(current_geom)  depth=$(current_depth)  fps=$(current_fps)"
  echo "Desktop compositor: $(xfconf-query -c xfwm4 -p /general/use_compositing 2>/dev/null || echo n/a)"
  echo -n "Plank: "
  pgrep -x plank >/dev/null 2>&1 && echo running || echo stopped
  echo -n "xfdesktop: "
  pgrep -x xfdesktop >/dev/null 2>&1 && echo running || echo stopped
  echo "Load: $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || true)"
  df -h / | tail -n 1
  free -h | awk 'NR==1 || NR==2'
}

main() {
  echo "=============================="
  echo " Slimcast desktop speedup"
  echo "=============================="
  echo
  echo "Target: ${TARGET_GEOM} ${TARGET_DEPTH}-bit ${TARGET_FPS}fps"
  echo

  write_vnc_config
  if vnc_needs_restart; then
    restart_vnc || true
  else
    echo "VNC already at target frame rate/depth."
    shrink_display
  fi

  tune_desktop
  stop_plank
  stop_xfdesktop
  clean_caches
  print_status
  echo
  echo "If the viewer went blank, refresh the Slimcast tab."
}

main "$@"
