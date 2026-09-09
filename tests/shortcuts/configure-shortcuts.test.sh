#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
tool="${repo_dir}/bin/configure-shortcuts"
fake_hyprctl="${repo_dir}/tests/shortcuts/fake-hyprctl"
empty_bindings="${repo_dir}/tests/shortcuts/fixtures/empty.json"
conflict_bindings="${repo_dir}/tests/shortcuts/fixtures/conflicts.json"
custom_owned_bindings="${repo_dir}/tests/shortcuts/fixtures/custom-owned.json"
custom_conflict_bindings="${repo_dir}/tests/shortcuts/fixtures/custom-conflicts.json"
malformed_record_bindings="${repo_dir}/tests/shortcuts/fixtures/malformed-record.json"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1" expected="$2"
  grep -Fq -- "$expected" "$file" || fail "${file} does not contain: ${expected}"
}

assert_not_contains() {
  local file="$1" unexpected="$2"
  if grep -Fq -- "$unexpected" "$file"; then
    fail "${file} unexpectedly contains: ${unexpected}"
  fi
}

backup_count() {
  local config="$1"
  find "$(dirname -- "$config")" -maxdepth 1 -type f \
    -name "$(basename -- "$config").bak.*" -printf . | wc -c
}

config="${test_dir}/bindings.lua"
expected_original="${test_dir}/expected-original.lua"
printf '%s\n' \
  '-- user prefix' \
  'o.bind("SUPER + J", "Personal launcher", "personal-launcher")' \
  '-- user suffix' >"$config"
cp -- "$config" "$expected_original"

absent_hash="$(sha256sum "$config" | cut -d' ' -f1)"
"$tool" status --json --config "$config" >"${test_dir}/status-absent.json"
jq -e '.ok == true and .configured == false and .minimizeBinding == ""
  and .sidebarBinding == ""' "${test_dir}/status-absent.json" >/dev/null \
  || fail "absent JSON status is not machine-readable and explicit"
[[ "$(sha256sum "$config" | cut -d' ' -f1)" == "$absent_hash" ]] \
  || fail "read-only absent JSON status changed the config"
[[ "$(backup_count "$config")" == 0 ]] \
  || fail "read-only absent JSON status created a backup"

log="${test_dir}/hyprctl.log"
: >"$log"
OMARCHY_MINIMIZE_FAKE_LOG="$log" \
  "$tool" check --minimize-binding 'super + shift + k' \
  --sidebar-binding 'mouse:276' --json --config "$config" \
  --hyprctl "$fake_hyprctl" \
  >"${test_dir}/check-free.json"
jq -e '.ok == true and .pairAvailable == true and .duplicate == false
  and .minimize.input == "super + shift + k"
  and .minimize.binding == "SUPER + SHIFT + K"
  and .minimize.valid == true and .minimize.available == true
  and .sidebar.binding == "mouse:276" and .sidebar.available == true
  and (.minimize.conflicts | length) == 0 and (.sidebar.conflicts | length) == 0' \
  "${test_dir}/check-free.json" >/dev/null \
  || fail "read-only free-pair check did not return the expected JSON schema"
[[ "$(sha256sum "$config" | cut -d' ' -f1)" == "$absent_hash" ]] \
  || fail "read-only free-pair check changed the config"
[[ "$(backup_count "$config")" == 0 ]] \
  || fail "read-only free-pair check created a backup"
[[ "$(paste -sd, "$log")" == 'binds -j' ]] \
  || fail "read-only free-pair check did more than inspect active bindings"

: >"$log"
"$tool" check --minimize-binding 'super + m' \
  --sidebar-binding 'super + alt + m' --json --config "$config" \
  --bindings-json "$conflict_bindings" --hyprctl "$fake_hyprctl" \
  >"${test_dir}/check-conflicts.json"
jq -e '.ok == true and .pairAvailable == false
  and .minimize.available == false and .minimize.conflicts == ["Personal mail"]
  and .sidebar.available == false and .sidebar.conflicts == ["Personal menu"]' \
  "${test_dir}/check-conflicts.json" >/dev/null \
  || fail "read-only conflict check did not name both active owners"

"$tool" check --minimize-binding 'SUPER + Q' \
  --sidebar-binding 'super+q' --json --config "$config" \
  --bindings-json "$empty_bindings" --hyprctl "$fake_hyprctl" \
  >"${test_dir}/check-duplicate.json"
jq -e '.ok == true and .pairAvailable == false and .duplicate == true
  and .minimize.available == false and .sidebar.available == false
  and (.minimize.message | contains("Open minimize sidebar"))
  and (.sidebar.message | contains("Minimize focused window"))' \
  "${test_dir}/check-duplicate.json" >/dev/null \
  || fail "read-only check did not explain the internal action collision"

"$tool" check --minimize-binding 'SUPER + M")' \
  --sidebar-binding '' --json --config "$config" \
  --bindings-json "$empty_bindings" --hyprctl "$fake_hyprctl" \
  >"${test_dir}/check-invalid.json"
jq -e '.ok == true and .pairAvailable == false
  and .minimize.valid == false and (.minimize.message | contains("unsupported chord syntax"))
  and .sidebar.valid == false and (.sidebar.message | contains("Record or enter"))' \
  "${test_dir}/check-invalid.json" >/dev/null \
  || fail "read-only check did not return actionable invalid/empty field feedback"
[[ "$(sha256sum "$config" | cut -d' ' -f1)" == "$absent_hash" ]] \
  || fail "read-only validation checks changed the config"
[[ "$(backup_count "$config")" == 0 ]] \
  || fail "read-only validation checks created a backup"

OMARCHY_MINIMIZE_FAKE_LOG="$log" \
  "$tool" add --config "$config" --hyprctl "$fake_hyprctl" >"${test_dir}/add.out"
assert_contains "$config" '-- BEGIN osouthgate.minimize shortcuts'
assert_contains "$config" 'o.bind("SUPER + M", "Minimize active window", "omarchy-shell osouthgate.minimize minimize")'
assert_contains "$config" 'o.bind("SUPER + ALT + M", "Toggle minimized windows", "omarchy-shell shell toggle osouthgate.minimize")'
assert_contains "$config" '-- END osouthgate.minimize shortcuts'
[[ "$(backup_count "$config")" == 1 ]] || fail "successful add did not create exactly one backup"
first_backup="$(find "$test_dir" -maxdepth 1 -type f -name 'bindings.lua.bak.*' -print -quit)"
cmp -s -- "$first_backup" "$expected_original" || fail "add backup does not match the original bytes"
[[ "$(paste -sd, "$log")" == 'binds -j,reload,configerrors' ]] \
  || fail "add did not inspect once, reload, then validate: $(paste -sd, "$log")"
"$tool" status --config "$config" --hyprctl "$fake_hyprctl" >"${test_dir}/status.out"
assert_contains "${test_dir}/status.out" 'SUPER + M -> omarchy-shell osouthgate.minimize minimize'
assert_contains "${test_dir}/status.out" 'SUPER + ALT + M -> omarchy-shell shell toggle osouthgate.minimize'
"$tool" status --json --config "$config" >"${test_dir}/status-configured.json"
jq -e '.ok == true and .configured == true and .minimizeBinding == "SUPER + M"
  and .sidebarBinding == "SUPER + ALT + M"' "${test_dir}/status-configured.json" >/dev/null \
  || fail "configured JSON status did not return the canonical pair"

before_idempotent="$(sha256sum "$config" | cut -d' ' -f1)"
"$tool" add --config "$config" --hyprctl "$fake_hyprctl" >"${test_dir}/idempotent.out"
after_idempotent="$(sha256sum "$config" | cut -d' ' -f1)"
[[ "$before_idempotent" == "$after_idempotent" ]] || fail "idempotent add changed the config"
[[ "$(backup_count "$config")" == 1 ]] || fail "idempotent add created an unnecessary backup"

apply_config="${test_dir}/apply-bindings.lua"
printf '%s\n' '-- apply fixture' >"$apply_config"
OMARCHY_MINIMIZE_FAKE_LOG="$log" \
  "$tool" apply --minimize-binding 'mouse:0275' \
    --sidebar-binding 'super + n' --config "$apply_config" \
    --bindings-json "$empty_bindings" --hyprctl "$fake_hyprctl" \
    >"${test_dir}/apply-add.out"
assert_contains "$apply_config" 'o.bind("mouse:275", "Minimize active window", "omarchy-shell osouthgate.minimize minimize")'
assert_contains "$apply_config" 'o.bind("SUPER + N", "Toggle minimized windows", "omarchy-shell shell toggle osouthgate.minimize")'
OMARCHY_MINIMIZE_FAKE_LOG="$log" \
  "$tool" apply --minimize-binding 'super + minus' \
    --sidebar-binding 'ctrl + super + n' --config "$apply_config" \
    --bindings-json "$empty_bindings" --hyprctl "$fake_hyprctl" \
    >"${test_dir}/apply-update.out"
assert_contains "$apply_config" 'o.bind("SUPER + MINUS", "Minimize active window", "omarchy-shell osouthgate.minimize minimize")'
assert_contains "$apply_config" 'o.bind("SUPER + CTRL + N", "Toggle minimized windows", "omarchy-shell shell toggle osouthgate.minimize")'
apply_hash="$(sha256sum "$apply_config" | cut -d' ' -f1)"
apply_backups="$(backup_count "$apply_config")"
"$tool" apply --minimize-binding 'SUPER + MINUS' \
  --sidebar-binding 'SUPER + CTRL + N' --config "$apply_config" \
  --bindings-json "$empty_bindings" --hyprctl "$fake_hyprctl" \
  >"${test_dir}/apply-idempotent.out"
[[ "$(sha256sum "$apply_config" | cut -d' ' -f1)" == "$apply_hash" ]] \
  || fail "idempotent apply changed the config"
[[ "$(backup_count "$apply_config")" == "$apply_backups" ]] \
  || fail "idempotent apply created an unnecessary backup"

lock_path="${test_dir}/held-shortcut.lock"
exec 9>"$lock_path"
flock -n 9 || fail "could not acquire the fixture shortcut lock"
locked_hash="$(sha256sum "$apply_config" | cut -d' ' -f1)"
locked_backups="$(backup_count "$apply_config")"
if OMARCHY_MINIMIZE_SHORTCUT_LOCK="$lock_path" \
    "$tool" apply --minimize-binding 'SUPER + Q' \
      --sidebar-binding 'SUPER + CTRL + Q' --config "$apply_config" \
      --bindings-json "$empty_bindings" --hyprctl "$fake_hyprctl" \
      >"${test_dir}/apply-locked.out" 2>&1; then
  fail "concurrent apply ignored the held shortcut lock"
fi
flock -u 9
exec 9>&-
[[ "$(sha256sum "$apply_config" | cut -d' ' -f1)" == "$locked_hash" ]] \
  || fail "lock contention changed the config"
[[ "$(backup_count "$apply_config")" == "$locked_backups" ]] \
  || fail "lock contention created a backup"
assert_contains "${test_dir}/apply-locked.out" 'already running'

printf '%s\n' '-- unrelated tail after the owned block' >>"$config"
printf '%s\n' \
  '-- user prefix' \
  'o.bind("SUPER + J", "Personal launcher", "personal-launcher")' \
  '-- user suffix' \
  '-- unrelated tail after the owned block' >"${test_dir}/expected-remove.lua"
pre_remove="${test_dir}/pre-remove.lua"
cp -- "$config" "$pre_remove"
: >"$log"
OMARCHY_MINIMIZE_FAKE_LOG="$log" \
  "$tool" remove --config "$config" --hyprctl "$fake_hyprctl" >"${test_dir}/remove.out"
cmp -s -- "$config" "${test_dir}/expected-remove.lua" \
  || fail "remove changed bytes outside the owned block"
[[ "$(backup_count "$config")" == 2 ]] || fail "successful remove did not create a backup"
latest_backup="$(find "$test_dir" -maxdepth 1 -type f -name 'bindings.lua.bak.*' -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)"
cmp -s -- "$latest_backup" "$pre_remove" || fail "remove backup does not match pre-mutation bytes"
[[ "$(paste -sd, "$log")" == 'reload,configerrors' ]] \
  || fail "remove did not reload then validate: $(paste -sd, "$log")"

cp -- "$expected_original" "$config"
find "$test_dir" -maxdepth 1 -type f -name 'bindings.lua.bak.*' -delete
before_conflict="$(sha256sum "$config" | cut -d' ' -f1)"
if "$tool" add --config "$config" --bindings-json "$conflict_bindings" \
    --hyprctl "$fake_hyprctl" >"${test_dir}/conflict.out" 2>&1; then
  fail "conflicting shortcut pair was accepted"
fi
after_conflict="$(sha256sum "$config" | cut -d' ' -f1)"
[[ "$after_conflict" == "$before_conflict" ]] || fail "conflict changed the binding file"
[[ "$(backup_count "$config")" == 0 ]] || fail "conflict created a backup despite making no mutation"
assert_contains "${test_dir}/conflict.out" 'SUPER + M is already bound to Personal mail'
assert_contains "${test_dir}/conflict.out" 'SUPER + ALT + M is already bound to Personal menu'

cp -- "$expected_original" "$config"
find "$test_dir" -maxdepth 1 -type f -name 'bindings.lua.bak.*' -delete
: >"$log"
OMARCHY_MINIMIZE_FAKE_LOG="$log" \
  "$tool" add --minimize-binding 'mouse:0275' \
    --sidebar-binding 'shift + win + p' --config "$config" \
    --bindings-json "$empty_bindings" --hyprctl "$fake_hyprctl" \
    >"${test_dir}/custom-add.out"
assert_contains "$config" 'o.bind("mouse:275", "Minimize active window", "omarchy-shell osouthgate.minimize minimize")'
assert_contains "$config" 'o.bind("SUPER + SHIFT + P", "Toggle minimized windows", "omarchy-shell shell toggle osouthgate.minimize")'
assert_not_contains "$config" '{ mouse = true'
"$tool" status --config "$config" >"${test_dir}/custom-status.out"
assert_contains "${test_dir}/custom-status.out" 'mouse:275 -> omarchy-shell osouthgate.minimize minimize'
assert_contains "${test_dir}/custom-status.out" 'SUPER + SHIFT + P -> omarchy-shell shell toggle osouthgate.minimize'

printf '%s\n' '-- user tail after custom block' >>"$config"
pre_custom_update="${test_dir}/pre-custom-update.lua"
cp -- "$config" "$pre_custom_update"
custom_backups_before="$(backup_count "$config")"
: >"$log"
OMARCHY_MINIMIZE_FAKE_LOG="$log" \
  "$tool" update --minimize-binding 'control + alt + k' --config "$config" \
    --bindings-json "$custom_owned_bindings" --hyprctl "$fake_hyprctl" \
    >"${test_dir}/custom-update.out"
assert_contains "$config" 'o.bind("CTRL + ALT + K", "Minimize active window", "omarchy-shell osouthgate.minimize minimize")'
assert_contains "$config" 'o.bind("SUPER + SHIFT + P", "Toggle minimized windows", "omarchy-shell shell toggle osouthgate.minimize")'
[[ "$(tail -n 1 "$config")" == '-- user tail after custom block' ]] \
  || fail "update moved or changed bytes following the owned block"
[[ "$(backup_count "$config")" == $((custom_backups_before + 1)) ]] \
  || fail "custom update did not create exactly one backup"
[[ "$(paste -sd, "$log")" == 'reload,configerrors' ]] \
  || fail "update did not reuse the loaded binding snapshot then validate: $(paste -sd, "$log")"

before_same_update="$(sha256sum "$config" | cut -d' ' -f1)"
same_update_backups="$(backup_count "$config")"
"$tool" update --minimize-binding 'CTRL + ALT + K' --config "$config" \
  --bindings-json "$empty_bindings" --hyprctl "$fake_hyprctl" \
  >"${test_dir}/same-update.out"
[[ "$(sha256sum "$config" | cut -d' ' -f1)" == "$before_same_update" ]] \
  || fail "same-spec update changed the config"
[[ "$(backup_count "$config")" == "$same_update_backups" ]] \
  || fail "same-spec update created an unnecessary backup"

before_custom_conflict="$(sha256sum "$config" | cut -d' ' -f1)"
custom_conflict_backups="$(backup_count "$config")"
if "$tool" update --minimize-binding 'mouse:276' \
    --sidebar-binding 'SUPER + CTRL + K' --config "$config" \
    --bindings-json "$custom_conflict_bindings" --hyprctl "$fake_hyprctl" \
    >"${test_dir}/custom-conflict.out" 2>&1; then
  fail "custom keyboard and mouse conflicts were accepted"
fi
[[ "$(sha256sum "$config" | cut -d' ' -f1)" == "$before_custom_conflict" ]] \
  || fail "custom conflict changed the config"
[[ "$(backup_count "$config")" == "$custom_conflict_backups" ]] \
  || fail "custom conflict created a backup"
assert_contains "${test_dir}/custom-conflict.out" 'mouse:276 is already bound to Personal mouse action'
assert_contains "${test_dir}/custom-conflict.out" 'SUPER + CTRL + K is already bound to Personal keyboard action'

before_malformed_record="$(sha256sum "$config" | cut -d' ' -f1)"
malformed_record_backups="$(backup_count "$config")"
if "$tool" update --sidebar-binding 'SUPER + CTRL + K' --config "$config" \
    --bindings-json "$malformed_record_bindings" --hyprctl "$fake_hyprctl" \
    >"${test_dir}/malformed-record.out" 2>&1; then
  fail "malformed active binding record was treated as conflict-free"
fi
[[ "$(sha256sum "$config" | cut -d' ' -f1)" == "$before_malformed_record" ]] \
  || fail "malformed active binding record changed the config"
[[ "$(backup_count "$config")" == "$malformed_record_backups" ]] \
  || fail "malformed active binding record created a backup"
assert_contains "${test_dir}/malformed-record.out" 'could not interpret active Hyprland bindings'

before_duplicate="$(sha256sum "$config" | cut -d' ' -f1)"
if "$tool" update --minimize-binding 'SUPER + Q' --sidebar-binding 'super+q' \
    --config "$config" --bindings-json "${test_dir}/does-not-exist.json" \
    --hyprctl "$fake_hyprctl" >"${test_dir}/duplicate.out" 2>&1; then
  fail "one chord was accepted for two plugin actions"
fi
[[ "$(sha256sum "$config" | cut -d' ' -f1)" == "$before_duplicate" ]] \
  || fail "internal collision refusal changed the config"
assert_contains "${test_dir}/duplicate.out" 'cannot use the same chord'

for hostile in 'SUPER + M")' 'mouse:271' 'mouse:272' 'mouse:768' 'code:42' \
    'SUPER + SUPER + K' $'SUPER + M\nBAD' 'SUPER + Ü'; do
  before_hostile="$(sha256sum "$config" | cut -d' ' -f1)"
  hostile_backups="$(backup_count "$config")"
  if "$tool" update --minimize-binding "$hostile" --config "$config" \
      --bindings-json "${test_dir}/does-not-exist.json" --hyprctl "$fake_hyprctl" \
      >"${test_dir}/hostile.out" 2>&1; then
    fail "unsafe or unsupported chord was accepted: ${hostile}"
  fi
  [[ "$(sha256sum "$config" | cut -d' ' -f1)" == "$before_hostile" ]] \
    || fail "invalid chord changed the config: ${hostile}"
  [[ "$(backup_count "$config")" == "$hostile_backups" ]] \
    || fail "invalid chord created a backup: ${hostile}"
done

custom_installed="${test_dir}/custom-installed.lua"
cp -- "$config" "$custom_installed"
custom_rollback_backups="$(backup_count "$config")"
: >"$log"
if OMARCHY_MINIMIZE_FAKE_LOG="$log" OMARCHY_MINIMIZE_FAKE_CONFIG_ERRORS='synthetic update error' \
    "$tool" update --minimize-binding 'mouse:277' --config "$config" \
      --bindings-json "$empty_bindings" --hyprctl "$fake_hyprctl" \
      >"${test_dir}/update-rollback.out" 2>&1; then
  fail "configerrors failure was accepted during update"
fi
cmp -s -- "$config" "$custom_installed" \
  || fail "failed update did not roll back byte-for-byte"
[[ "$(backup_count "$config")" == $((custom_rollback_backups + 1)) ]] \
  || fail "failed update did not retain exactly one new backup"
assert_contains "${test_dir}/update-rollback.out" 'synthetic update error'
assert_contains "${test_dir}/update-rollback.out" 'restored'

cp -- "$expected_original" "$config"
find "$test_dir" -maxdepth 1 -type f -name 'bindings.lua.bak.*' -delete
: >"$log"
before_rollback="$(sha256sum "$config" | cut -d' ' -f1)"
if OMARCHY_MINIMIZE_FAKE_LOG="$log" OMARCHY_MINIMIZE_FAKE_CONFIG_ERRORS='synthetic config error' \
    "$tool" add --config "$config" --bindings-json "$empty_bindings" \
      --hyprctl "$fake_hyprctl" >"${test_dir}/add-rollback.out" 2>&1; then
  fail "configerrors failure was accepted during add"
fi
after_rollback="$(sha256sum "$config" | cut -d' ' -f1)"
[[ "$after_rollback" == "$before_rollback" ]] || fail "failed add did not roll back byte-for-byte"
[[ "$(backup_count "$config")" == 1 ]] || fail "failed add did not retain exactly one backup"
assert_contains "${test_dir}/add-rollback.out" 'synthetic config error'
assert_contains "${test_dir}/add-rollback.out" 'restored'
[[ "$(paste -sd, "$log")" == 'reload,configerrors,reload' ]] \
  || fail "failed add did not validate and reload rollback: $(paste -sd, "$log")"

find "$test_dir" -maxdepth 1 -type f -name 'bindings.lua.bak.*' -delete
"$tool" add --config "$config" --bindings-json "$empty_bindings" \
  --hyprctl "$fake_hyprctl" >/dev/null
installed="${test_dir}/installed.lua"
cp -- "$config" "$installed"
find "$test_dir" -maxdepth 1 -type f -name 'bindings.lua.bak.*' -delete
: >"$log"
if OMARCHY_MINIMIZE_FAKE_LOG="$log" OMARCHY_MINIMIZE_FAKE_CONFIG_ERRORS='synthetic remove error' \
    "$tool" remove --config "$config" --hyprctl "$fake_hyprctl" \
      >"${test_dir}/remove-rollback.out" 2>&1; then
  fail "configerrors failure was accepted during remove"
fi
cmp -s -- "$config" "$installed" || fail "failed remove did not roll back byte-for-byte"
[[ "$(backup_count "$config")" == 1 ]] || fail "failed remove did not retain exactly one backup"
assert_contains "${test_dir}/remove-rollback.out" 'synthetic remove error'
assert_contains "${test_dir}/remove-rollback.out" 'restored'

malformed="${test_dir}/malformed.lua"
printf '%s\n' \
  '-- BEGIN osouthgate.minimize shortcuts' \
  'o.bind("SUPER + M", "broken", "broken")' >"$malformed"
before_malformed="$(sha256sum "$malformed" | cut -d' ' -f1)"
if "$tool" remove --config "$malformed" --hyprctl "$fake_hyprctl" \
    >"${test_dir}/malformed.out" 2>&1; then
  fail "malformed ownership markers were accepted"
fi
[[ "$(sha256sum "$malformed" | cut -d' ' -f1)" == "$before_malformed" ]] \
  || fail "malformed marker refusal changed the config"
if "$tool" status --json --config "$malformed" >"${test_dir}/malformed-status.out" 2>&1; then
  fail "malformed owned block returned successful JSON status"
fi
[[ "$(sha256sum "$malformed" | cut -d' ' -f1)" == "$before_malformed" ]] \
  || fail "malformed JSON status changed the config"

no_newline="${test_dir}/no-newline.lua"
printf '%s' '-- user data without a final newline' >"$no_newline"
before_no_newline="$(sha256sum "$no_newline" | cut -d' ' -f1)"
if "$tool" add --config "$no_newline" --bindings-json "$empty_bindings" \
    --hyprctl "$fake_hyprctl" >"${test_dir}/no-newline.out" 2>&1; then
  fail "add accepted a config without a final newline"
fi
[[ "$(sha256sum "$no_newline" | cut -d' ' -f1)" == "$before_no_newline" ]] \
  || fail "newline refusal changed the config"
[[ "$(backup_count "$no_newline")" == 0 ]] || fail "newline refusal created a backup"

symlink_target="${test_dir}/symlink-target.lua"
symlink_config="${test_dir}/symlink-bindings.lua"
printf '%s\n' '-- symlink target' >"$symlink_target"
ln -s -- "$symlink_target" "$symlink_config"
"$tool" add --config "$symlink_config" --bindings-json "$empty_bindings" \
  --hyprctl "$fake_hyprctl" >/dev/null
[[ -L "$symlink_config" ]] || fail "mutation replaced the binding-file symlink"
assert_contains "$symlink_target" '-- BEGIN osouthgate.minimize shortcuts'
[[ "$(backup_count "$symlink_target")" == 1 ]] || fail "symlink target mutation was not backed up"

printf '%s\n' \
  'SHORTCUT_CHECK free=yes conflict=named duplicate=blocked invalid=explained mutation=no' \
  'SHORTCUT_ADD exit=0 chords="SUPER + M|SUPER + ALT + M" backup=yes validation="reload,configerrors"' \
  'SHORTCUT_CUSTOM exit=0 keyboard=yes mouse=yes canonical=yes normal-bind=yes' \
  'SHORTCUT_CONFLICT exit=1 chords="SUPER + M|SUPER + ALT + M" unchanged=yes backup=no' \
  'SHORTCUT_UPDATE exit=0 partial=yes self-exclusion=yes in-place=yes rollback=byte-identical' \
  'SHORTCUT_JSON absent=exit-0 configured=exit-0 malformed=exit-1 mutation=no' \
  'SHORTCUT_APPLY add=yes update=yes idempotent=yes lock-contention=unchanged' \
  'SHORTCUT_ROLLBACK exit=1 add=byte-identical remove=byte-identical' \
  'SHORTCUT_REMOVE exit=0 scope=owned-block unchanged=unrelated-bytes backup=yes' \
  'ok - read-only shortcut check canonicalizes drafts, names conflicts, and gates duplicate or invalid pairs' \
  'ok - shortcut add checks one live snapshot and installs the complete pair' \
  'ok - shortcut add is idempotent and status reports both commands' \
  'ok - shortcut conflict names both occupied chords and performs no edit' \
  'ok - custom keyboard and mouse bindings are canonicalized and status is truthful' \
  'ok - JSON status is read-only for absent, configured, and malformed ownership states' \
  'ok - idempotent apply adds or updates under a nonblocking cross-process lock' \
  'ok - partial update preserves the other action and replaces the owned block in place' \
  'ok - custom conflicts, internal collisions, and hostile chord text fail before mutation' \
  'ok - every mutation is backed up and reload precedes configerrors' \
  'ok - add validation failure rolls back byte-for-byte' \
  'ok - remove validation failure rolls back byte-for-byte' \
  'ok - remove deletes only the exact owned block' \
  'ok - malformed ownership and missing-newline inputs fail closed' \
  'ok - binding-file symlinks retain their identity and mutate their backed-up target'
