#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
config_dir="$(mktemp -d)"
runtime_dir="$(mktemp -d)"
log_file="$(mktemp)"
ipc_file="$(mktemp)"
lint_file="$(mktemp)"
shell_pid=""

cleanup() {
  if [[ -n "$shell_pid" ]] && kill -0 "$shell_pid" 2>/dev/null; then
    kill "$shell_pid" 2>/dev/null || true
    wait "$shell_pid" 2>/dev/null || true
  fi
  rm -rf -- "$config_dir" "$runtime_dir"
  rm -f -- "$log_file" "$ipc_file" "$lint_file"
}
trap cleanup EXIT

chmod 700 "$runtime_dir"
cp -- "$repo_dir/tests/QmlServiceHarness.qml" "$config_dir/shell.qml"
cp -- "$repo_dir/Service.qml" "$repo_dir/MinimizeModel.js" \
  "$repo_dir/CompositorTransaction.js" "$config_dir/"
mkdir -p "$config_dir/imports/qs"
ln -s /usr/share/omarchy/shell/Commons "$config_dir/imports/qs/Commons"
ln -s /usr/share/omarchy/shell/Ui "$config_dir/imports/qs/Ui"

env -u DISPLAY -u WAYLAND_DISPLAY -u GTK_THEME -u XDG_CURRENT_DESKTOP -u XDG_SESSION_DESKTOP -u DESKTOP_SESSION XDG_RUNTIME_DIR="$runtime_dir" HYPRLAND_INSTANCE_SIGNATURE="test-instance" QT_QPA_PLATFORM=minimal QT_QPA_PLATFORMTHEME= QT_STYLE_OVERRIDE=Fusion quickshell -vv --no-color --path "$config_dir/shell.qml" >"$log_file" 2>&1 &
shell_pid=$!

for _ in $(seq 1 120); do
  if rg -q 'OMARCHY_MINIMIZE_SERVICE_PASS|OMARCHY_MINIMIZE_SERVICE_ERROR' "$log_file"; then
    break
  fi
  if ! kill -0 "$shell_pid" 2>/dev/null; then
    break
  fi
  sleep 0.05
done

if ! rg -q 'OMARCHY_MINIMIZE_SERVICE_PASS' "$log_file" || rg -q 'OMARCHY_MINIMIZE_SERVICE_ERROR' "$log_file"; then
  sed -n '1,260p' "$log_file" >&2
  exit 1
fi

for method in status minimize restore restoreOrigin restoreHere restoreLast restoreAll acknowledge reconcile prepareRemoval cancelRemoval; do
  args=()
  case "$method" in
    restore|restoreOrigin|restoreHere|acknowledge) args=("0x1") ;;
  esac
  output="$(
    XDG_RUNTIME_DIR="$runtime_dir" QT_QPA_PLATFORM=minimal quickshell ipc --any-display --path "$config_dir/shell.qml" call osouthgate.minimize "$method" "${args[@]}" 2>&1
  )"
  printf '%s=%s\n' "$method" "$output" >>"$ipc_file"
  node -e 'JSON.parse(process.argv[1])' "$output"
done

if rg -n 'QQml.*[Ee]rror|failed to load|is not a type|Cannot assign|ReferenceError|TypeError' "$log_file"; then
  sed -n '1,260p' "$log_file" >&2
  exit 1
fi

if ! /usr/lib/qt6/bin/qmllint --ignore-settings -I "$config_dir/imports" "$repo_dir/Service.qml" "$repo_dir/Panel.qml" >"$lint_file" 2>&1; then
  sed -n '1,260p' "$lint_file" >&2
  exit 1
fi

sed -n '/OMARCHY_MINIMIZE_MINIMIZE_ORDER/p;/OMARCHY_MINIMIZE_RESTORE_ORDER/p;/OMARCHY_MINIMIZE_ADOPTED/p;/OMARCHY_MINIMIZE_STALE_CLEAN/p;/OMARCHY_MINIMIZE_ROLLBACK/p;/OMARCHY_MINIMIZE_ADDRESS_REUSE/p;/OMARCHY_MINIMIZE_RELOAD_RECOVERY/p;/OMARCHY_MINIMIZE_MANUAL_MOVE_CLEANUP/p;/OMARCHY_MINIMIZE_SEMANTIC_REFUSAL/p;/OMARCHY_MINIMIZE_WRITE_AHEAD_GUARD/p;/OMARCHY_MINIMIZE_COMMAND_ROLLBACK/p;/OMARCHY_MINIMIZE_EVENT_BURST/p;/OMARCHY_MINIMIZE_MULTI_EXTERNAL_CLEANUP/p;/OMARCHY_MINIMIZE_CLEANUP_RACE/p;/OMARCHY_MINIMIZE_CLEANUP_RETRY/p;/OMARCHY_MINIMIZE_CLEANUP_WRITE_GUARD/p;/OMARCHY_MINIMIZE_MONITOR_FALLBACK/p;/OMARCHY_MINIMIZE_ORIGIN_ROUTING/p;/OMARCHY_MINIMIZE_SHORTCUT_SERVICE/p;/OMARCHY_MINIMIZE_PENDING_MINIMIZE/p;/OMARCHY_MINIMIZE_PENDING_RESTORE/p;/OMARCHY_MINIMIZE_HIDDEN_CLOSE/p;/OMARCHY_MINIMIZE_REMOVAL_DRAIN/p;/OMARCHY_MINIMIZE_IPC_STATUS/p' "$log_file"
expected_ipc_methods='status,minimize,restore,restoreOrigin,restoreHere,restoreLast,restoreAll,acknowledge,reconcile,prepareRemoval,cancelRemoval'
actual_ipc_methods="$(cut -d= -f1 "$ipc_file" | paste -sd, -)"
if [[ "$actual_ipc_methods" != "$expected_ipc_methods" ]]; then
  printf 'unexpected IPC method inventory: %s\n' "$actual_ipc_methods" >&2
  exit 1
fi
printf 'IPC methods: %s\n' "$actual_ipc_methods"
printf '%s\n' 'ok - singleton service transactions, reconciliation, rollback, persistence guards, and IPC surface passed'
