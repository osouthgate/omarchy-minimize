#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
config_dir="$(mktemp -d)"
native_config_dir="$(mktemp -d)"
runtime_dir="$(mktemp -d)"
log_file="$(mktemp)"
native_log_file="$(mktemp)"
lint_file="$(mktemp)"
artifact_dir="${repo_dir}/tests/artifacts/ui"
shell_pid=""
native_pid=""

cleanup() {
  if [[ -n "$shell_pid" ]] && kill -0 "$shell_pid" 2>/dev/null; then
    kill "$shell_pid" 2>/dev/null || true
    wait "$shell_pid" 2>/dev/null || true
  fi
  if [[ -n "$native_pid" ]] && kill -0 "$native_pid" 2>/dev/null; then
    kill "$native_pid" 2>/dev/null || true
    wait "$native_pid" 2>/dev/null || true
  fi
  rm -rf -- "$config_dir" "$native_config_dir" "$runtime_dir"
  rm -f -- "$log_file" "$native_log_file" "$lint_file"
}
trap cleanup EXIT

chmod 700 "$runtime_dir"
mkdir -p "$artifact_dir" "$config_dir/imports/qs"
capture_names=(empty populated updated urgent long-list help shortcuts recording)
for capture_name in "${capture_names[@]}"; do
  rm -f -- "$artifact_dir/$capture_name.png"
done

cp -- "$repo_dir/tests/QmlSmokeHarness.qml" "$config_dir/shell.qml"
cp -- "$repo_dir/Panel.qml" "$repo_dir/WindowRow.qml" \
  "$repo_dir/HelpView.qml" "$repo_dir/ShortcutSettingsView.qml" "$config_dir/"
ln -s /usr/share/omarchy/shell/Commons "$config_dir/imports/qs/Commons"
cp -a -- /usr/share/omarchy/shell/Ui "$config_dir/imports/qs/Ui"
cp -- "$repo_dir/tests/fixtures/Ui/KeyboardPanel.qml" \
  "$config_dir/imports/qs/Ui/KeyboardPanel.qml"

rg -q 'KeyboardPanel[[:space:]]*\{' "$repo_dir/Panel.qml"
rg -q 'x:[[:space:]]*1000000' "$repo_dir/Panel.qml"
rg -q 'tooltipText:[[:space:]]*"Restore every listed window to this screen' "$repo_dir/Panel.qml"
rg -q 'Accessible.name:[[:space:]]*"Minimized windows"' "$repo_dir/Panel.qml"
rg -q 'Accessible.name:[[:space:]]*"Reconcile minimized windows"' "$repo_dir/Panel.qml"
rg -q 'Accessible.name:[[:space:]]*"Restore all minimized windows here"' "$repo_dir/Panel.qml"
rg -q 'Accessible.name:[[:space:]]*"Open Omarchy Minimize help"' "$repo_dir/Panel.qml"
rg -q 'Accessible.name:[[:space:]]*"Configure minimize shortcuts"' "$repo_dir/Panel.qml"
rg -q 'Accessible.name:[[:space:]]*"Back to minimized windows"' "$repo_dir/Panel.qml"
rg -q 'Accessible.name:[[:space:]]*"Save both shortcuts"' "$repo_dir/ShortcutSettingsView.qml"
rg -q 'textFormat:[[:space:]]*Text.PlainText' "$repo_dir/HelpView.qml"
rg -q 'ScrollView[[:space:]]*\{' "$repo_dir/HelpView.qml"
rg -q 'ScrollView[[:space:]]*\{' "$repo_dir/ShortcutSettingsView.qml"
rg -q 'tooltipText:[[:space:]]*\{' "$repo_dir/Panel.qml"
rg -q 'tooltipText:[[:space:]]*"Reconcile with live windows"' "$repo_dir/Panel.qml"
[[ "$(rg -c 'Accessible.description:[[:space:]]*tooltipText' "$repo_dir/Panel.qml")" -ge 3 ]]
rg -q 'Accessible.name:[[:space:]]*root.title' "$repo_dir/WindowRow.qml"
rg -q 'PanelToolTip[[:space:]]*\{' "$repo_dir/WindowRow.qml"
rg -q 'Color.popups.background' "$repo_dir/tests/QmlSmokeHarness.qml"
rg -q 'Color.popups.text' "$repo_dir/tests/QmlSmokeHarness.qml"
rg -q 'Style.spacing' "$repo_dir/tests/QmlSmokeHarness.qml"
if rg -n '#[[:xdigit:]]{3,8}|color:[[:space:]]*"(white|black|transparent)"' \
    "$repo_dir/Panel.qml" "$repo_dir/WindowRow.qml" "$repo_dir/HelpView.qml" \
    "$repo_dir/ShortcutSettingsView.qml" "$repo_dir/tests/QmlSmokeHarness.qml"; then
  printf 'hardcoded UI palette found in product QML or capture facade\n' >&2
  exit 1
fi

env -u DISPLAY -u WAYLAND_DISPLAY -u GTK_THEME -u XDG_CURRENT_DESKTOP \
  -u XDG_SESSION_DESKTOP -u DESKTOP_SESSION \
  XDG_RUNTIME_DIR="$runtime_dir" HYPRLAND_INSTANCE_SIGNATURE="ui-fixture" \
  QML2_IMPORT_PATH="$config_dir/imports" QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME= QT_STYLE_OVERRIDE=Fusion QT_QUICK_BACKEND=software \
  OMARCHY_MINIMIZE_ARTIFACT_DIR="$artifact_dir" \
  quickshell -vv --no-color --path "$config_dir/shell.qml" >"$log_file" 2>&1 &
shell_pid=$!

for _ in $(seq 1 200); do
  if rg -q 'OMARCHY_MINIMIZE_UI_PASS|OMARCHY_MINIMIZE_UI_ERROR' "$log_file"; then
    break
  fi
  if ! kill -0 "$shell_pid" 2>/dev/null; then
    break
  fi
  sleep 0.05
done

if ! rg -q 'OMARCHY_MINIMIZE_UI_PASS' "$log_file" \
    || rg -q 'OMARCHY_MINIMIZE_UI_ERROR' "$log_file"; then
  sed -n '1,320p' "$log_file" >&2
  exit 1
fi

required_markers=(
  'OMARCHY_MINIMIZE_UI_STATES empty,loading,error,unsupported,pending,updated,urgent,recovered,origin-missing'
  'OMARCHY_MINIMIZE_UI_KEYBOARD open,M,Enter,Shift+Enter,Ctrl+Enter,A,R,Escape'
  'OMARCHY_MINIMIZE_UI_ACCESSIBILITY row-name=literal row-description=state+origin'
  'OMARCHY_MINIMIZE_UI_LONG_LIST rows=100 selected=99 contained=true'
  'OMARCHY_MINIMIZE_UI_PERF rows=100 hyprctl=0'
  'OMARCHY_MINIMIZE_UI_PAGES help=covered shortcuts=states back=before-close reopen=windows'
  'OMARCHY_MINIMIZE_UI_SHORTCUTS open=read-only record=keyboard+mouse conflict=named save=gated+once refresh=read-only remove=confirmed shared=preserved'
  'OMARCHY_MINIMIZE_UI_FOCUS fields=bypass F1=help Escape=back-then-close width=320 scroll=true'
  'OMARCHY_MINIMIZE_UI_RESTORE_CLOSE queued=open success=closed failure=open manual-cancel=preserved all=open'
)
for marker in "${required_markers[@]}"; do
  if ! rg -Fq "$marker" "$log_file"; then
    printf 'missing deterministic UI assertion marker: %s\n' "$marker" >&2
    sed -n '1,320p' "$log_file" >&2
    exit 1
  fi
done

for image in "${capture_names[@]}"; do
  image_path="$artifact_dir/$image.png"
  if [[ ! -s "$image_path" ]]; then
    printf 'missing UI capture: %s\n' "$image_path" >&2
    exit 1
  fi
  if ! file "$image_path" | rg -q 'PNG image data, 520 x 600'; then
    file "$image_path" >&2
    exit 1
  fi
done

if rg -n 'QQml.*[Ee]rror|failed to load|is not a type|Cannot assign|ReferenceError|TypeError|Binding loop' "$log_file"; then
  sed -n '1,320p' "$log_file" >&2
  exit 1
fi

if ! /usr/lib/qt6/bin/qmllint --ignore-settings -I "$config_dir/imports" \
    "$config_dir/Panel.qml" "$config_dir/WindowRow.qml" "$config_dir/HelpView.qml" \
    "$config_dir/ShortcutSettingsView.qml" "$config_dir/shell.qml" \
    >"$lint_file" 2>&1; then
  sed -n '1,320p' "$lint_file" >&2
  exit 1
fi

# Load once more against Omarchy's real KeyboardPanel/PanelWindow backend.
# The fixture never opens it, so this is an API-compatibility check without a
# visible surface or compositor mutation.
if [[ -z "${WAYLAND_DISPLAY:-}" || -z "${XDG_RUNTIME_DIR:-}" \
    || ! -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]]; then
  printf 'real KeyboardPanel load requires an active Wayland session\n' >&2
  exit 1
fi
mkdir -p "$native_config_dir/imports/qs"
cp -- "$repo_dir/tests/QmlNativeLoadHarness.qml" "$native_config_dir/shell.qml"
cp -- "$repo_dir/Panel.qml" "$repo_dir/WindowRow.qml" \
  "$repo_dir/HelpView.qml" "$repo_dir/ShortcutSettingsView.qml" "$native_config_dir/"
ln -s /usr/share/omarchy/shell/Commons "$native_config_dir/imports/qs/Commons"
ln -s /usr/share/omarchy/shell/Ui "$native_config_dir/imports/qs/Ui"

QML2_IMPORT_PATH="$native_config_dir/imports" QT_QPA_PLATFORM=wayland \
  QT_QPA_PLATFORMTHEME= QT_STYLE_OVERRIDE=Fusion \
  quickshell -vv --no-color --path "$native_config_dir/shell.qml" \
  >"$native_log_file" 2>&1 &
native_pid=$!
for _ in $(seq 1 120); do
  if rg -q 'OMARCHY_MINIMIZE_NATIVE_PASS|OMARCHY_MINIMIZE_NATIVE_ERROR' "$native_log_file"; then
    break
  fi
  if ! kill -0 "$native_pid" 2>/dev/null; then
    break
  fi
  sleep 0.05
done
if ! rg -q 'OMARCHY_MINIMIZE_NATIVE_PASS' "$native_log_file" \
    || rg -q 'OMARCHY_MINIMIZE_NATIVE_ERROR|Failed to load configuration|No PanelWindow backend loaded' \
      "$native_log_file"; then
  sed -n '1,260p' "$native_log_file" >&2
  exit 1
fi
if rg -n 'QQml.*[Ee]rror|failed to load|is not a type|Cannot assign|ReferenceError|TypeError|Binding loop' \
    "$native_log_file"; then
  sed -n '1,260p' "$native_log_file" >&2
  exit 1
fi

sed -n \
  -e '/OMARCHY_MINIMIZE_UI_BADGE/p' \
  -e '/OMARCHY_MINIMIZE_UI_MOUSE/p' \
  -e '/OMARCHY_MINIMIZE_UI_ROW/p' \
  -e '/OMARCHY_MINIMIZE_UI_ACCESSIBILITY/p' \
  -e '/OMARCHY_MINIMIZE_UI_MONITORS/p' \
  -e '/OMARCHY_MINIMIZE_UI_KEYBOARD/p' \
  -e '/OMARCHY_MINIMIZE_UI_MESSAGES/p' \
  -e '/OMARCHY_MINIMIZE_UI_STATES/p' \
  -e '/OMARCHY_MINIMIZE_UI_BOUNDS/p' \
  -e '/OMARCHY_MINIMIZE_UI_LAYOUT/p' \
  -e '/OMARCHY_MINIMIZE_UI_PERF/p' \
  -e '/OMARCHY_MINIMIZE_UI_LONG_LIST/p' \
  -e '/OMARCHY_MINIMIZE_UI_PAGES/p' \
  -e '/OMARCHY_MINIMIZE_UI_SHORTCUTS/p' \
  -e '/OMARCHY_MINIMIZE_UI_FOCUS/p' \
  -e '/OMARCHY_MINIMIZE_UI_RESTORE_CLOSE/p' \
  -e '/OMARCHY_MINIMIZE_UI_SCREENSHOT/p' \
  "$log_file"
sed -n '/OMARCHY_MINIMIZE_NATIVE_PASS/p' "$native_log_file"
printf '%s\n' \
  'ok - bar actions, fixed badge priority, row semantics, and keyboard routing passed' \
  'ok - two monitor panels shared one store and emitted distinct restore targets' \
  'ok - all nine visible states and icon/row accessibility contracts passed' \
  'ok - hostile Unicode/plain-text bounds and 100-row containment/zero-query projection passed' \
  "ok - empty, populated, updated, urgent, long-list, help, shortcuts, and recording PNG captures written under $artifact_dir"
