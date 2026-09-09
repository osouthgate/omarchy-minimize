.pragma library

// Pure state and validation rules shared by QML and dependency-free Node tests.
// This module never invokes the compositor.

var COMPATIBLE_WORKSPACES = {
  "special:minimum": true,
  "special:minimized": true,
  "special:scratchpad": true
}

var ATTENTION_NONE = "none"
var ATTENTION_UPDATED = "updated"
var ATTENTION_URGENT = "urgent"
var MAX_SIGNED_INT = 2147483647

function hasOwn(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key)
}

function clean(value) {
  return String(value === undefined || value === null ? "" : value).trim()
}

function ownValue(object, key, fallback) {
  return object && hasOwn(object, key) ? object[key] : fallback
}

function firstValue(values, fallback) {
  for (var i = 0; i < values.length; i++) {
    if (values[i] !== undefined && values[i] !== null && values[i] !== "")
      return values[i]
  }
  return fallback
}

function workspaceName(workspace) {
  if (typeof workspace === "string" || typeof workspace === "number")
    return clean(workspace)
  if (!workspace) return ""
  if (workspace.name !== undefined && workspace.name !== null && clean(workspace.name))
    return clean(workspace.name)
  if (workspace.id !== undefined && workspace.id !== null)
    return clean(workspace.id)
  return ""
}

function isCompatibleWorkspace(workspace) {
  return hasOwn(COMPATIBLE_WORKSPACES, workspaceName(workspace))
}

function isSpecialWorkspace(workspace) {
  return workspaceName(workspace).indexOf("special:") === 0
}

function normalizeAddress(address) {
  var value = clean(address)
  return /^0x[0-9a-fA-F]{1,16}$/.test(value) ? value.toLowerCase() : ""
}

function addressSelector(address) {
  var normalized = normalizeAddress(address)
  return normalized ? "address:" + normalized : ""
}

function isSafeNamedWorkspace(value) {
  return /^name:[A-Za-z0-9][A-Za-z0-9 ._:+-]{0,126}$/.test(value)
}

function normalWorkspaceTarget(workspace) {
  if (workspace && typeof workspace === "object") {
    var numericId = Number(workspace.id)
    if (isFinite(numericId) && numericId > 0 && numericId <= MAX_SIGNED_INT
        && Math.floor(numericId) === numericId)
      return String(numericId)
  }

  var name = workspaceName(workspace)
  if (/^[1-9][0-9]{0,9}$/.test(name) && Number(name) <= MAX_SIGNED_INT)
    return String(Number(name))
  if (/^[0-9]+$/.test(name)) return ""
  if (isSafeNamedWorkspace(name) && name.indexOf("special:") !== 0) return name
  if (/^[A-Za-z0-9][A-Za-z0-9 ._+-]{0,126}$/.test(name))
    return "name:" + name
  return ""
}

function isValidWorkspaceTarget(workspace, allowCompatibleSpecial) {
  var name = workspaceName(workspace)
  if (allowCompatibleSpecial && isCompatibleWorkspace(name)) return true
  return normalWorkspaceTarget(workspace) !== ""
}

function luaStringLiteral(value, kind) {
  var text = clean(value)
  if (kind === "address") {
    text = addressSelector(text)
    if (!text) return ""
  } else if (kind === "selector") {
    if (!/^address:0x[0-9a-fA-F]{1,16}$/.test(text)) return ""
  } else if (kind === "workspace") {
    if (!isValidWorkspaceTarget(text, true)) return ""
    text = isCompatibleWorkspace(text) ? text : normalWorkspaceTarget(text)
  } else {
    return ""
  }
  return JSON.stringify(text)
}

function ipcObject(client) {
  return ownValue(client, "lastIpcObject", {}) || {}
}

function clientField(client, key, fallback) {
  var ipc = ipcObject(client)
  return firstValue([
    ownValue(client, key, undefined),
    ownValue(ipc, key, undefined)
  ], fallback)
}

function initialClass(client) {
  var wayland = ownValue(client, "wayland", {}) || {}
  return clean(firstValue([
    clientField(client, "initialClass", ""),
    ownValue(wayland, "appId", ""),
    clientField(client, "class", "")
  ], ""))
}

function initialTitle(client) {
  return clean(firstValue([
    clientField(client, "initialTitle", ""),
    clientField(client, "title", "")
  ], ""))
}

function clientPid(client) {
  var number = Number(clientField(client, "pid", 0))
  return isFinite(number) && number > 0 && number <= MAX_SIGNED_INT
    && Math.floor(number) === number ? number : 0
}

function compositorStableId(client) {
  var value = clean(clientField(client, "stableId", "")).toLowerCase()
  if (!/^[0-9a-f]{1,16}$/.test(value)) return ""
  return value.replace(/^0+(?=[0-9a-f])/, "")
}

function initialIdentity(client) {
  return initialClass(client) + "\u001f" + initialTitle(client)
}

function stableClientId(client) {
  var explicit = compositorStableId(client)
  if (explicit) return explicit
  return String(clientPid(client)) + "\u001f" + initialIdentity(client)
}

function clientWorkspace(client) {
  return workspaceName(firstValue([
    ownValue(client, "workspace", undefined),
    ownValue(ipcObject(client), "workspace", undefined)
  ], ""))
}

function clientTitle(client) {
  return clean(clientField(client, "title", ""))
}

function clientClass(client) {
  return clean(firstValue([
    clientField(client, "class", ""),
    initialClass(client)
  ], ""))
}

function clientMonitor(client) {
  var value = Number(clientField(client, "monitor", -1))
  return isFinite(value) && Math.floor(value) === value ? value : -1
}

function isPinned(client) {
  return clientField(client, "pinned", false) === true
}

function isGrouped(client) {
  var grouped = clientField(client, "grouped", [])
  if (Array.isArray(grouped)) return grouped.length > 0
  return grouped === true || (typeof grouped === "string" && clean(grouped) !== "")
}

function normalizeClient(client) {
  var source = client || {}
  return {
    address: normalizeAddress(clientField(source, "address", "")),
    workspace: clientWorkspace(source),
    pid: clientPid(source),
    compositorStableId: compositorStableId(source),
    stableId: stableClientId(source),
    initialIdentity: initialIdentity(source),
    initialClass: initialClass(source),
    initialTitle: initialTitle(source),
    title: clientTitle(source),
    className: clientClass(source),
    monitor: clientMonitor(source),
    urgent: clientField(source, "urgent", false) === true,
    pinned: isPinned(source),
    grouped: isGrouped(source)
  }
}

function cloneRecord(record) {
  var result = {}
  var source = record || {}
  for (var key in source) {
    if (hasOwn(source, key)) result[key] = source[key]
  }
  return result
}

function recordMatchesClient(record, rawClient, instanceSignature) {
  if (!record) return false
  var client = normalizeClient(rawClient)
  var signature = clean(instanceSignature)
  return signature !== ""
    && clean(record.instanceSignature) === signature
    && normalizeAddress(record.address) !== ""
    && normalizeAddress(record.address) === client.address
    && Number(record.pid) > 0
    && Number(record.pid) === client.pid
    && clean(record.compositorStableId) !== ""
    && clean(record.compositorStableId).toLowerCase() === client.compositorStableId
}

function attentionFor(record, rawClient) {
  var client = normalizeClient(rawClient)
  var previous = clean(record && record.attention)
  if (previous === ATTENTION_URGENT || client.urgent) return ATTENTION_URGENT
  if (previous === ATTENTION_UPDATED) return ATTENTION_UPDATED
  var baseline = String(ownValue(record, "baselineTitle", ""))
  if (client.title && client.title !== baseline) return ATTENTION_UPDATED
  return ATTENTION_NONE
}

function attentionLabel(attention) {
  if (attention === ATTENTION_URGENT) return "Needs attention"
  if (attention === ATTENTION_UPDATED) return "Updated"
  return "Minimized"
}

function createRecord(rawClient, instanceSignature, options) {
  var client = normalizeClient(rawClient)
  var opts = options || {}
  var now = Number(ownValue(opts, "now", Date.now()))
  var baselineTitle = ownValue(opts, "baselineTitle", client.title)
  return {
    address: client.address,
    instanceSignature: clean(instanceSignature),
    pid: client.pid,
    compositorStableId: client.compositorStableId,
    stableId: client.stableId,
    initialIdentity: client.initialIdentity,
    initialClass: client.initialClass,
    initialTitle: client.initialTitle,
    className: client.className,
    title: client.title,
    baselineTitle: String(baselineTitle === undefined || baselineTitle === null ? "" : baselineTitle),
    sourceWorkspace: client.workspace,
    origin: clean(ownValue(opts, "origin", "")),
    monitor: client.monitor,
    minimizedAt: isFinite(now) ? now : Date.now(),
    attention: ATTENTION_NONE,
    owned: ownValue(opts, "owned", false) === true,
    recovered: ownValue(opts, "recovered", false) === true
  }
}

function updateRecord(record, rawClient) {
  var client = normalizeClient(rawClient)
  var updated = cloneRecord(record)
  updated.title = client.title
  updated.className = client.className
  updated.monitor = client.monitor
  updated.sourceWorkspace = client.workspace
  updated.attention = attentionFor(record, client)
  return updated
}

function reconcile(rawClients, records, instanceSignature, now) {
  var signature = clean(instanceSignature)
  var previousByAddress = {}
  var oldRecords = Array.isArray(records) ? records : []
  for (var r = 0; r < oldRecords.length; r++) {
    var recordAddress = normalizeAddress(oldRecords[r] && oldRecords[r].address)
    if (recordAddress && !hasOwn(previousByAddress, recordAddress))
      previousByAddress[recordAddress] = oldRecords[r]
  }

  var result = []
  var seen = {}
  var clients = Array.isArray(rawClients) ? rawClients : []
  for (var i = 0; i < clients.length; i++) {
    var client = normalizeClient(clients[i])
    if (!client.address || !client.pid || !client.compositorStableId
        || !isCompatibleWorkspace(client.workspace) || hasOwn(seen, client.address))
      continue
    seen[client.address] = true
    var previous = previousByAddress[client.address]
    if (recordMatchesClient(previous, client, signature)) {
      result.push(updateRecord(previous, client))
    } else {
      var adopted = createRecord(client, signature, {
        now: now,
        owned: false,
        recovered: previous !== undefined
      })
      adopted.attention = client.urgent ? ATTENTION_URGENT : ATTENTION_NONE
      result.push(adopted)
    }
  }
  return result
}

function acknowledge(record) {
  var result = cloneRecord(record)
  result.attention = ATTENTION_NONE
  result.baselineTitle = clean(result.title)
  return result
}

function failure(code, message) {
  return { ok: false, code: code, message: message }
}

function planMinimize(rawClient, instanceSignature, now) {
  if (!rawClient) return failure("no-active-window", "No active window to minimize.")
  var client = normalizeClient(rawClient)
  if (!client.address) return failure("invalid-address", "The active window address is invalid.")
  if (isCompatibleWorkspace(client.workspace))
    return failure("already-minimized", "This window is already minimized.")
  if (isSpecialWorkspace(client.workspace))
    return failure("unsupported-special-workspace", "Move this special-workspace window to a normal workspace first.")
  if (client.pinned) return failure("pinned-window", "Unpin this window before minimizing it.")
  if (client.grouped) return failure("grouped-window", "Remove this window from its group before minimizing it.")
  if (!client.pid || !client.compositorStableId)
    return failure("unstable-identity", "The active window does not expose a stable identity.")
  var origin = normalWorkspaceTarget(rawClient.workspace || ipcObject(rawClient).workspace)
  if (!origin) return failure("invalid-origin", "The active window's workspace cannot be restored safely.")
  var signature = clean(instanceSignature)
  if (!signature) return failure("missing-instance", "The compositor instance is unavailable.")
  return {
    ok: true,
    code: "ready",
    address: client.address,
    selector: addressSelector(client.address),
    destination: "special:minimum",
    origin: origin,
    record: createRecord(client, signature, {
      now: now,
      origin: origin,
      owned: true
    })
  }
}

function workspaceExists(target, workspaces) {
  var normalizedTarget = normalWorkspaceTarget(target)
  if (!normalizedTarget) return false
  var list = Array.isArray(workspaces) ? workspaces : []
  for (var i = 0; i < list.length; i++) {
    if (normalWorkspaceTarget(list[i]) === normalizedTarget) return true
  }
  return false
}

function planRestore(record, fallbackWorkspace, preferOrigin, workspaces) {
  if (preferOrigin === true) {
    var originTarget = normalWorkspaceTarget(record && record.origin)
    if (originTarget && workspaceExists(originTarget, workspaces)) {
      return {
        ok: true,
        code: "restore-origin",
        target: originTarget,
        usedOrigin: true,
        reason: ""
      }
    }
  }

  var fallbackTarget = normalWorkspaceTarget(fallbackWorkspace)
  if (!fallbackTarget)
    return failure("no-visible-workspace", "No visible workspace is available for restore.")

  return {
    ok: true,
    code: preferOrigin === true ? "restore-here-fallback" : "restore-here",
    target: fallbackTarget,
    usedOrigin: false,
    reason: preferOrigin === true
      ? "Original workspace is unavailable; restoring here instead." : ""
  }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    COMPATIBLE_WORKSPACES: COMPATIBLE_WORKSPACES,
    ATTENTION_NONE: ATTENTION_NONE,
    ATTENTION_UPDATED: ATTENTION_UPDATED,
    ATTENTION_URGENT: ATTENTION_URGENT,
    workspaceName: workspaceName,
    isCompatibleWorkspace: isCompatibleWorkspace,
    isSpecialWorkspace: isSpecialWorkspace,
    normalWorkspaceTarget: normalWorkspaceTarget,
    isValidWorkspaceTarget: isValidWorkspaceTarget,
    normalizeAddress: normalizeAddress,
    addressSelector: addressSelector,
    luaStringLiteral: luaStringLiteral,
    normalizeClient: normalizeClient,
    stableClientId: stableClientId,
    compositorStableId: compositorStableId,
    initialIdentity: initialIdentity,
    recordMatchesClient: recordMatchesClient,
    attentionFor: attentionFor,
    attentionLabel: attentionLabel,
    createRecord: createRecord,
    updateRecord: updateRecord,
    reconcile: reconcile,
    acknowledge: acknowledge,
    planMinimize: planMinimize,
    workspaceExists: workspaceExists,
    planRestore: planRestore
  }
}
