.pragma library

// Pure builders for address-scoped Hyprland Lua transactions. Only bounded
// ASCII identifiers and workspace selectors can enter generated Lua.

var COMPATIBLE_WORKSPACES = {
  "special:minimum": true,
  "special:minimized": true,
  "special:scratchpad": true
}

var MAX_SIGNED_INT = 2147483647

function clean(value) {
  return String(value === undefined || value === null ? "" : value).trim()
}

function normalizeAddress(value) {
  var text = clean(value)
  return /^0x[0-9a-fA-F]{1,16}$/.test(text) ? text.toLowerCase() : ""
}

function normalizeStableId(value) {
  var text = clean(value).toLowerCase()
  if (!/^[0-9a-f]{1,16}$/.test(text)) return ""
  return text.replace(/^0+(?=[0-9a-f])/, "")
}

function positivePid(value) {
  var number = Number(value)
  return isFinite(number) && number > 0 && number <= MAX_SIGNED_INT
    && Math.floor(number) === number ? number : 0
}

function numericWorkspace(value) {
  var text = clean(value)
  if (!/^[1-9][0-9]{0,9}$/.test(text)) return ""
  var number = Number(text)
  return number <= MAX_SIGNED_INT ? String(number) : ""
}

function namedWorkspace(value) {
  var text = clean(value)
  return /^name:[A-Za-z0-9][A-Za-z0-9 ._:+-]{0,126}$/.test(text)
    && text.indexOf("special:") !== 0 ? text : ""
}

function workspaceSpec(value, allowCompatible) {
  var text = clean(value)
  if (allowCompatible && COMPATIBLE_WORKSPACES[text] === true) {
    return { dispatch: text, kind: "name", membership: text, condition: function(variable) {
      return variable + " and " + variable + ".name==" + luaAscii(text)
    } }
  }
  var numeric = numericWorkspace(text)
  if (numeric) {
    return { dispatch: numeric, kind: "numeric", membership: numeric, condition: function(variable) {
      return variable + " and " + variable + ".id==" + numeric
    } }
  }
  var named = namedWorkspace(text)
  if (named) {
    var membership = named.slice(5)
    return { dispatch: named, kind: "name", membership: membership, condition: function(variable) {
      return variable + " and " + variable + ".name==" + luaAscii(membership)
    } }
  }
  return null
}

function compactWorkspace(spec, prefix) {
  if (!spec || !/^[a-z]$/.test(prefix)) return null
  if (spec.kind === "numeric") {
    return {
      declaration: "local " + prefix + "n," + prefix + "d=" + spec.membership + ","
        + luaAscii(spec.dispatch) + ";",
      dispatch: prefix + "d",
      condition: function(variable) {
        return variable + " and " + variable + ".id==" + prefix + "n"
      }
    }
  }
  var namedPrefix = spec.dispatch.indexOf("name:") === 0 ? "\"name:\".." : ""
  return {
    declaration: "local " + prefix + "n=" + luaAscii(spec.membership) + ";local "
      + prefix + "d=" + (namedPrefix ? namedPrefix + prefix + "n" : prefix + "n") + ";",
    dispatch: prefix + "d",
    condition: function(variable) {
      return variable + " and " + variable + ".name==" + prefix + "n"
    }
  }
}

function recordIdentity(record) {
  var source = record || {}
  var address = normalizeAddress(source.address)
  var pid = positivePid(source.pid)
  var stableId = normalizeStableId(source.compositorStableId)
  if (!address || !pid || !stableId) return null
  return { address: address, pid: pid, stableId: stableId }
}

function luaAscii(value) {
  var text = String(value)
  if (!/^[\x20-\x7e]*$/.test(text)) return ""
  return JSON.stringify(text)
}

function guardedPrelude(record) {
  var identity = recordIdentity(record)
  if (!identity) return ""
  return [
    "local a,p,s=", luaAscii(identity.address), ",", String(identity.pid), ",",
    luaAscii(identity.stableId), ";local g,d,v=hl.get_window,hl.dispatch,hl.dsp.window;local z=\"address:\"..a;",
    "local function q(x)return x and x.mapped and x.address==a and x.pid==p and type(x.stable_id)==\"number\" and string.format(\"%x\",x.stable_id)==s end;",
    "local w=g(z);if not w then return\"REFUSE:MISSING\"end;if not q(w)then return\"REFUSE:STALE\"end;"
  ].join("")
}

function step(kind, operations, successReplies, lua) {
  if (!lua || !/^[\x09\x0a\x0d\x20-\x7e]*$/.test(lua)) return null
  // Compact source avoids needless pressure on Hyprland's control socket.
  lua = lua.replace(/\r?\n/g, ";")
  if (!/^[\x20-\x7e]*$/.test(lua)) return null
  // Hyprland 0.56.2 reads at most 1023 bytes and cannot reliably frame a
  // longer SOCK_STREAM request. `/repl ` consumes six of the safe 1022 bytes.
  if (lua.length > 1016) return null
  return {
    kind: kind,
    operations: operations.slice(),
    successReplies: successReplies.slice(),
    argv: ["hyprctl", "repl", lua]
  }
}

function dispatchSucceeded(variable) {
  return variable + " and " + variable + ".ok"
}

function minimizeStep(record, destination) {
  var prelude = guardedPrelude(record)
  var source = workspaceSpec(record && record.origin, false)
  var target = workspaceSpec(destination, true)
  if (!prelude || !source || !target || COMPATIBLE_WORKSPACES[target.dispatch] !== true)
    return null

  return step("guarded-minimize", ["set-override", "move"], ["OK:MINIMIZED"], [
    prelude,
    "if w.pinned then return\"REFUSE:PINNED\"end;if w.group then return\"REFUSE:GROUPED\"end;",
    "if not(", source.condition("w.workspace"), ")then return\"REFUSE:SOURCE\"end;",
    "local r=d(v.set_prop({prop=\"focus_on_activate\",value=\"0\",window=w}));",
    "if not(r and r.ok)then return\"ERROR:SETPROP\"end;",
    "d(v.move({workspace=", luaAscii(target.dispatch), ",follow=false,window=w}));w=g(z);",
    "if q(w)and(", target.condition("w.workspace"), ")then return\"OK:MINIMIZED\"end;",
    "if not q(w)then return\"ERROR:LOST_AFTER_MOVE\"end;",
    "return\"ERROR:MOVE\""
  ].join(""))
}

function restoreMoveStep(record, targetWorkspace) {
  var prelude = guardedPrelude(record)
  var source = workspaceSpec(record && record.sourceWorkspace, true)
  var target = workspaceSpec(targetWorkspace, false)
  var targetBound = compactWorkspace(target, "t")
  if (!prelude || !source || !targetBound || COMPATIBLE_WORKSPACES[source.dispatch] !== true)
    return null

  return step("guarded-restore", ["move"], ["OK:RESTORE_MOVED"], [
    prelude,
    "if w.pinned then return\"REFUSE:PINNED\"end;if w.group then return\"REFUSE:GROUPED\"end;",
    "if not(", source.condition("w.workspace"), ")then return\"REFUSE:MEMBERSHIP\"end;",
    targetBound.declaration,
    "d(v.move({workspace=", targetBound.dispatch, ",follow=false,window=w}));w=g(z);",
    "if q(w)and(", targetBound.condition("w.workspace"), ")then return\"OK:RESTORE_MOVED\"end;",
    "if not q(w)then return\"ERROR:LOST_AFTER_MOVE\"end;return\"ERROR:MOVE\""
  ].join(""))
}

function postRestoreStep(record, targetWorkspace, unsetOverride) {
  var prelude = guardedPrelude(record)
  var target = workspaceSpec(targetWorkspace, false)
  if (!prelude || !target) return null
  var operations = ["focus"]
  var lines = [
    prelude,
    "if not(", target.condition("w.workspace"), ")then return\"REFUSE:TARGET\"end;",
    "local r=d(hl.dsp.focus({window=w}));local f=r and r.ok;"
  ]
  if (unsetOverride === true) {
    operations.push("unset-override")
    lines.push("local u=d(v.set_prop({prop=\"focus_on_activate\",value=\"unset\",window=w}));local o=u and u.ok;")
    lines.push("if not f and not o then return\"ERROR:FOCUS_AND_UNSET\"end;if not o then return\"ERROR:UNSET\"end;")
  }
  lines.push("if not f then return\"ERROR:FOCUS\"end;return\"OK:RESTORED\"")
  return step("guarded-post-restore", operations, ["OK:RESTORED"], lines.join(""))
}

function cleanupStep(record, expectedWorkspace) {
  var prelude = guardedPrelude(record)
  var target = workspaceSpec(expectedWorkspace, false)
  if (!prelude || !target || !record || record.owned !== true) return null
  return step("guarded-cleanup", ["unset-override"], ["OK:CLEANED"], [
    prelude,
    "if not(", target.condition("w.workspace"), ")then return\"REFUSE:TARGET\"end;",
    "local r=d(v.set_prop({prop=\"focus_on_activate\",value=\"unset\",window=w}));",
    "if not(r and r.ok)then return\"ERROR:UNSET\"end;return\"OK:CLEANED\""
  ].join(""))
}

function ensureHiddenOverrideStep(record) {
  var prelude = guardedPrelude(record)
  if (!prelude || !record || record.owned !== true) return null
  return step("guarded-ensure-hidden", ["set-override"], ["OK:PROTECTED"], [
    prelude,
    "local n=w.workspace and w.workspace.name;if not(n==\"special:minimum\" or n==\"special:minimized\" or n==\"special:scratchpad\")then return\"REFUSE:MEMBERSHIP\"end;",
    "local r=d(v.set_prop({prop=\"focus_on_activate\",value=\"0\",window=w}));",
    "if not(r and r.ok)then return\"ERROR:SETPROP\"end;return\"OK:PROTECTED\""
  ].join(""))
}

function minimizeResolutionStep(record, destination, kind, operations) {
  var prelude = guardedPrelude(record)
  var source = workspaceSpec(record && record.origin, false)
  var target = workspaceSpec(destination, true)
  var sourceBound = compactWorkspace(source, "b")
  var targetBound = compactWorkspace(target, "t")
  if (!prelude || !sourceBound || !targetBound || !record || record.owned !== true)
    return null
  return step(kind, operations,
    ["OK:MINIMIZED", "OK:ROLLED_BACK"], [
      prelude,
      sourceBound.declaration, targetBound.declaration,
      "if ", targetBound.condition("w.workspace"), " then return\"OK:MINIMIZED\"end;",
      "if not(", sourceBound.condition("w.workspace"), ")then d(v.move({workspace=",
      sourceBound.dispatch, ",follow=false,window=w}));w=g(z)end;",
      "if not q(w)or not(", sourceBound.condition("w.workspace"), ")then return\"ERROR:MOVE_ROLLBACK_FAILED\"end;",
      "local r=d(v.set_prop({prop=\"focus_on_activate\",value=\"unset\",window=w}));",
      "if not(r and r.ok)then return\"ERROR:UNSET\"end;return\"OK:ROLLED_BACK\""
    ].join(""))
}

function rollbackMinimizeStep(record, destination) {
  return minimizeResolutionStep(record, destination, "guarded-minimize-rollback",
    ["rollback-move", "unset-override"])
}

function resolveMinimizeStep(record, destination) {
  return minimizeResolutionStep(record, destination, "resolve-minimize", ["resolve-timeout"])
}

function resolveRestoreStep(record, targetWorkspace) {
  var prelude = guardedPrelude(record)
  var source = workspaceSpec(record && record.sourceWorkspace, true)
  var target = workspaceSpec(targetWorkspace, false)
  if (!prelude || !source || !target || COMPATIBLE_WORKSPACES[source.dispatch] !== true)
    return null
  return step("resolve-restore", ["resolve-restore"],
    ["OK:RESTORE_MOVED", "OK:ROLLED_BACK"], [
      prelude,
      "if ", target.condition("w.workspace"), " then return\"OK:RESTORE_MOVED\"end;",
      "if ", source.condition("w.workspace"), " then return\"OK:ROLLED_BACK\"end;",
      "d(v.move({workspace=", luaAscii(source.dispatch), ",follow=false,window=w}));w=g(z);",
      "if q(w)and(", source.condition("w.workspace"), ")then return\"OK:ROLLED_BACK\"end;",
      "return\"ERROR:MOVE_ROLLBACK_FAILED\""
    ].join(""))
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    normalizeAddress: normalizeAddress,
    normalizeStableId: normalizeStableId,
    numericWorkspace: numericWorkspace,
    workspaceSpec: workspaceSpec,
    recordIdentity: recordIdentity,
    minimizeStep: minimizeStep,
    restoreMoveStep: restoreMoveStep,
    postRestoreStep: postRestoreStep,
    cleanupStep: cleanupStep,
    ensureHiddenOverrideStep: ensureHiddenOverrideStep,
    rollbackMinimizeStep: rollbackMinimizeStep,
    resolveMinimizeStep: resolveMinimizeStep,
    resolveRestoreStep: resolveRestoreStep
  }
}
