const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

function loadQmlLibrary(relativePath) {
  const filename = path.join(__dirname, "..", relativePath)
  const source = fs.readFileSync(filename, "utf8").replace(/^\.pragma library\s*\r?\n/, "")
  const moduleShim = { exports: {} }
  Function("module", "exports", source)(moduleShim, moduleShim.exports)
  return moduleShim.exports
}

const Model = loadQmlLibrary("MinimizeModel.js")
const Transaction = loadQmlLibrary("CompositorTransaction.js")
const clients = require("./fixtures/clients.json")
const malicious = require("./fixtures/malicious.json")
const signature = "instance-2026"

function recordFor(client, options = {}) {
  return Model.createRecord(client, signature, {
    now: 1_700_000_000_000,
    origin: "2",
    owned: true,
    ...options
  })
}

test("exact workspace allowlist excludes unrelated special workspaces", () => {
  for (const name of ["special:minimum", "special:minimized", "special:scratchpad"])
    assert.equal(Model.isCompatibleWorkspace(name), true, name)
  assert.equal(Model.isCompatibleWorkspace("special:dropterm"), false)
  assert.equal(Model.isCompatibleWorkspace(clients.unrelatedSpecial.workspace), false)
})

test("reconciliation adopts each compatible live client once", () => {
  const actual = Model.reconcile([
    clients.minimum,
    clients.minimum,
    clients.dockMinimized,
    clients.scratchpad,
    clients.unrelatedSpecial,
    clients.normal
  ], [], signature, 1234)
  assert.deepEqual(actual.map((record) => record.address), ["0x2001", "0x2002", "0x2003"])
  assert.ok(actual.every((record) => record.owned === false))
})

test("reconciliation preserves a matching record and drops close or normal movement", () => {
  const record = recordFor(clients.minimum)
  assert.equal(Model.reconcile([clients.minimum], [record], signature, 2345)[0].owned, true)
  assert.deepEqual(Model.reconcile([], [record], signature, 2345), [])
  const restored = { ...clients.minimum, workspace: { id: 3, name: "3" } }
  assert.deepEqual(Model.reconcile([restored], [record], signature, 2345), [])
})

test("address reuse is rejected by session, address, PID, and real compositor stable ID", () => {
  const record = recordFor(clients.minimum)
  assert.equal(Model.recordMatchesClient(record, clients.minimum, signature), true)

  assert.equal(Model.recordMatchesClient(record, clients.minimum, "different-instance"), false)
  assert.equal(Model.recordMatchesClient({ ...record, compositorStableId: "deadbeef" }, clients.minimum,
    signature), false)
  assert.equal(Model.recordMatchesClient({ ...record, pid: record.pid + 1 }, clients.minimum, signature), false)
  assert.equal(Model.recordMatchesClient({ ...record, initialIdentity: "display metadata changed" },
    clients.minimum, signature), true)
  assert.equal(Model.recordMatchesClient(record, clients.addressReuse, signature), false)
  assert.equal(Model.recordMatchesClient(record, {
    ...clients.minimum,
    stableId: "2001b"
  }, signature), false)

  const adopted = Model.reconcile([clients.addressReuse], [record], signature, 3456)[0]
  assert.equal(adopted.pid, clients.addressReuse.pid)
  assert.equal(adopted.owned, false)
  assert.equal(adopted.recovered, true)
  assert.equal(adopted.origin, "")
})

test("urgent attention latches and outranks title updates", () => {
  const record = recordFor(clients.urgent, { baselineTitle: "Approval required" })
  const first = Model.updateRecord(record, clients.urgent)
  assert.equal(first.attention, Model.ATTENTION_URGENT)
  assert.equal(first.title, "Approval required")
  assert.equal(Model.updateRecord(first, { ...clients.urgent, urgent: false, title: "Idle" }).attention,
    Model.ATTENTION_URGENT)
  assert.equal(Model.attentionLabel(first.attention), "Needs attention")
})

test("only a post-minimize title change latches Updated", () => {
  const record = recordFor(clients.minimum, { baselineTitle: clients.minimum.title })
  assert.equal(Model.updateRecord(record, clients.minimum).attention, Model.ATTENTION_NONE)
  const changed = Model.updateRecord(record, { ...clients.minimum, title: "Build finished" })
  assert.equal(changed.attention, Model.ATTENTION_UPDATED)
  assert.equal(Model.updateRecord(changed, clients.minimum).attention, Model.ATTENTION_UPDATED)
  const acknowledged = Model.acknowledge(changed)
  assert.equal(acknowledged.attention, Model.ATTENTION_NONE)
  assert.equal(acknowledged.baselineTitle, "Build finished")
})

test("explicit restore-here targets the supplied normal workspace", () => {
  const planned = Model.planRestore(recordFor(clients.minimum), { id: 7, name: "7" }, false, [
    { id: 2, name: "2" },
    { id: 7, name: "7" }
  ])
  assert.deepEqual(planned, {
    ok: true,
    code: "restore-here",
    target: "7",
    usedOrigin: false,
    reason: ""
  })
})

test("origin-first restore does not require a fallback when its origin is live", () => {
  const record = recordFor(clients.minimum, { origin: "2" })
  const origin = Model.planRestore(record, null, true, [{ id: 2, name: "2" }])
  assert.equal(origin.target, "2")
  assert.equal(origin.usedOrigin, true)
  assert.equal(origin.reason, "")
})

test("origin-first restore returns a visible fallback reason", () => {
  const record = recordFor(clients.minimum, { origin: "2" })
  const fallback = Model.planRestore(record, { id: 7, name: "7" }, true, [
    { id: 7, name: "7" }
  ])
  assert.equal(fallback.target, "7")
  assert.equal(fallback.usedOrigin, false)
  assert.match(fallback.reason, /unavailable/)

  const refused = Model.planRestore(record, { id: -99, name: "special:minimum" }, true, [])
  assert.equal(refused.ok, false)
  assert.equal(refused.code, "no-visible-workspace")
})

test("minimize planning is exact and refuses unsafe client states", () => {
  const planned = Model.planMinimize(clients.normal, signature, 4567)
  assert.equal(planned.ok, true)
  assert.equal(planned.address, "0x1001")
  assert.equal(planned.selector, "address:0x1001")
  assert.equal(planned.destination, "special:minimum")
  assert.equal(planned.origin, "2")
  assert.equal(planned.record.owned, true)

  assert.equal(Model.planMinimize(null, signature).code, "no-active-window")
  assert.equal(Model.planMinimize(clients.minimum, signature).code, "already-minimized")
  assert.equal(Model.planMinimize(clients.unrelatedSpecial, signature).code, "unsupported-special-workspace")
  assert.equal(Model.planMinimize({ ...clients.normal, pinned: true }, signature).code, "pinned-window")
  assert.equal(Model.planMinimize({ ...clients.normal, grouped: ["0x1001"] }, signature).code, "grouped-window")
  assert.equal(Model.planMinimize({ ...clients.normal, stableId: "" }, signature).code, "unstable-identity")
  assert.equal(Model.planMinimize({ ...clients.normal, stableId: "not-hex" }, signature).code,
    "unstable-identity")
  assert.equal(Model.planMinimize({ ...clients.normal, pid: 2147483648 }, signature).code,
    "unstable-identity")
})

test("malicious addresses and workspaces cannot become Lua literals", () => {
  for (const value of malicious.invalidAddresses) {
    assert.equal(Model.normalizeAddress(value), "", value)
    assert.equal(Model.luaStringLiteral(value, "address"), "", value)
  }
  for (const value of malicious.validAddresses)
    assert.notEqual(Model.luaStringLiteral(value, "address"), "", value)

  for (const value of malicious.invalidWorkspaces)
    assert.equal(Model.luaStringLiteral(value, "workspace"), "", value)
  for (const value of malicious.validWorkspaces)
    assert.notEqual(Model.luaStringLiteral(value, "workspace"), "", value)
})

test("normalization supports Quickshell lastIpcObject and multi-monitor fields", () => {
  const normalized = Model.normalizeClient({
    address: "0xCAFE",
    title: "Visible title",
    urgent: true,
    workspace: { name: "special:minimum" },
    monitor: 2,
    lastIpcObject: {
      pid: 777,
      stableId: "a77",
      initialClass: "fixture",
      initialTitle: "Initial",
      grouped: []
    }
  })
  assert.equal(normalized.address, "0xcafe")
  assert.equal(normalized.pid, 777)
  assert.equal(normalized.compositorStableId, "a77")
  assert.equal(normalized.initialClass, "fixture")
  assert.equal(normalized.initialTitle, "Initial")
  assert.equal(normalized.monitor, 2)
  assert.equal(normalized.urgent, true)
})

test("reconciliation skips compatible clients without a bounded compositor identity", () => {
  assert.deepEqual(Model.reconcile([{ ...clients.minimum, stableId: "" }], [], signature, 1), [])
  assert.deepEqual(Model.reconcile([{ ...clients.minimum, stableId: "1".repeat(17) }], [], signature, 1), [])
  assert.deepEqual(Model.reconcile([{ ...clients.minimum, address: "0x" + "a".repeat(17) }], [],
    signature, 1), [])
})

test("workspace and address numeric bounds match Hyprland parsers", () => {
  assert.equal(Model.normalWorkspaceTarget("2147483647"), "2147483647")
  assert.equal(Model.normalWorkspaceTarget("2147483648"), "")
  assert.equal(Model.normalizeAddress("0x" + "f".repeat(16)), "0x" + "f".repeat(16))
  assert.equal(Model.normalizeAddress("0x" + "f".repeat(17)), "")
})

test("guarded minimize transaction validates identity before a silent move and postcondition", () => {
  const record = recordFor(clients.normal)
  const step = Transaction.minimizeStep(record, "special:minimum")
  assert.deepEqual(step.argv.slice(0, 2), ["hyprctl", "repl"])
  assert.deepEqual(step.operations, ["set-override", "move"])
  assert.deepEqual(step.successReplies, ["OK:MINIMIZED"])
  assert.match(step.argv[2], /string\.format\("%x",x\.stable_id\)==s/)
  assert.match(step.argv[2], /w\.pinned/)
  assert.match(step.argv[2], /w\.group/)
  assert.match(step.argv[2], /follow=false/)
  assert.match(step.argv[2], /w=g\(z\)/)
  assert.match(step.argv[2], /w\.workspace\.name=="special:minimum"/)
  assert.ok(step.argv[2].indexOf("local w=g") < step.argv[2].indexOf("set_prop"))
  assert.equal(step.argv[2].includes(clients.normal.title), false)
  assert.equal(step.argv[2].includes(clients.normal.class), false)
  assert.ok(step.argv[2].length <= 1016)

  const rollback = Transaction.rollbackMinimizeStep(record, "special:minimum")
  assert.deepEqual(rollback.operations, ["rollback-move", "unset-override"])
  assert.ok(rollback.argv[2].indexOf("v.move") < rollback.argv[2].indexOf("value=\"unset\""))
  assert.ok(rollback.argv[2].length <= 1016)
})

test("guarded restore uses exact numeric and named membership and preserves external overrides", () => {
  const owned = recordFor(clients.minimum)
  const numeric = Transaction.restoreMoveStep(owned, "7")
  assert.match(numeric.argv[2], /local tn,td=7,"7"/)
  assert.match(numeric.argv[2], /w\.workspace\.id==tn/)
  assert.match(numeric.argv[2], /workspace=td,follow=false/)

  const named = Transaction.restoreMoveStep(owned, "name:Project Alpha")
  assert.match(named.argv[2], /local tn="Project Alpha"/)
  assert.match(named.argv[2], /w\.workspace\.name==tn/)

  const external = { ...owned, owned: false }
  const finalizer = Transaction.postRestoreStep(external, "7", false)
  assert.deepEqual(finalizer.operations, ["focus"])
  assert.equal(finalizer.argv[2].includes("set_prop"), false)
  assert.match(finalizer.argv[2], /local r=d\(hl\.dsp\.focus\(\{window=w\}\)\);local f=r and r\.ok/)
  assert.equal(finalizer.argv[2].includes("hl.get_active_window"), false)

  const ownedFinalizer = Transaction.postRestoreStep(owned, "7", true)
  const targetProof = ownedFinalizer.argv[2].indexOf("w.workspace.id==7")
  const focusDispatch = ownedFinalizer.argv[2].indexOf("hl.dsp.focus")
  const unsetOverride = ownedFinalizer.argv[2].indexOf('value="unset"')
  assert.ok(targetProof >= 0 && targetProof < focusDispatch)
  assert.ok(focusDispatch < unsetOverride)
  assert.match(ownedFinalizer.argv[2], /ERROR:FOCUS_AND_UNSET/)
  assert.match(ownedFinalizer.argv[2], /ERROR:UNSET/)
  assert.match(ownedFinalizer.argv[2], /ERROR:FOCUS/)
  assert.ok(numeric.argv[2].length <= 1016)
  assert.ok(named.argv[2].length <= 1016)
  assert.ok(finalizer.argv[2].length <= 1016)
  assert.ok(ownedFinalizer.argv[2].length <= 1016)
})

test("cleanup proves one visible workspace before unsetting and recovery protects hidden aliases", () => {
  const owned = recordFor(clients.minimum)
  const cleanup = Transaction.cleanupStep(owned, "7")
  assert.deepEqual(cleanup.operations, ["unset-override"])
  assert.match(cleanup.argv[2], /w\.workspace\.id==7/)
  assert.match(cleanup.argv[2], /REFUSE:TARGET/)
  assert.ok(cleanup.argv[2].indexOf("w.workspace.id==7")
    < cleanup.argv[2].indexOf('value="unset"'))
  assert.equal(Transaction.cleanupStep(owned, "special:minimum"), null)

  const protector = Transaction.ensureHiddenOverrideStep(owned)
  assert.deepEqual(protector.operations, ["set-override"])
  for (const alias of ["special:minimum", "special:minimized", "special:scratchpad"])
    assert.match(protector.argv[2], new RegExp(alias.replace(":", "\\:")))
  assert.match(protector.argv[2], /REFUSE:MEMBERSHIP/)
  assert.ok(protector.argv[2].indexOf("w.workspace.name")
    < protector.argv[2].indexOf('value="0"'))
})

test("transaction builders reject unbounded or synthetic identities", () => {
  const record = recordFor(clients.normal)
  assert.equal(Transaction.minimizeStep({ ...record, compositorStableId: "" },
    "special:minimum"), null)
  assert.equal(Transaction.minimizeStep({ ...record, compositorStableId: "g123" },
    "special:minimum"), null)
  assert.equal(Transaction.minimizeStep({ ...record, pid: 2147483648 },
    "special:minimum"), null)
  assert.equal(Transaction.restoreMoveStep(recordFor(clients.minimum), "2147483648"), null)
})

test("every transaction builder rejects hostile dispatcher fields and excludes display data", () => {
  const ordinary = recordFor(clients.normal)
  const hidden = recordFor(clients.minimum)
  const hostileRecord = {
    ...ordinary,
    title: '"; os.execute("touch /tmp/pwned") --',
    className: "$(touch /tmp/pwned)",
    initialTitle: "`touch /tmp/pwned`"
  }
  const safeSteps = [
    Transaction.minimizeStep(hostileRecord, "special:minimum"),
    Transaction.restoreMoveStep({ ...hostileRecord, sourceWorkspace: "special:minimum" }, "7"),
    Transaction.postRestoreStep(hostileRecord, "7", true),
    Transaction.cleanupStep(hostileRecord, "7"),
    Transaction.ensureHiddenOverrideStep({ ...hostileRecord, sourceWorkspace: "special:minimum" }),
    Transaction.rollbackMinimizeStep(hostileRecord, "special:minimum"),
    Transaction.resolveMinimizeStep(hostileRecord, "special:minimum"),
    Transaction.resolveRestoreStep({ ...hostileRecord, sourceWorkspace: "special:minimum" }, "7")
  ]
  assert.ok(safeSteps.every(Boolean))
  for (const step of safeSteps) {
    assert.equal(step.argv[2].includes("touch /tmp/pwned"), false)
    assert.ok(step.argv[2].indexOf("x.address==a") < step.argv[2].indexOf("set_prop")
      || step.argv[2].indexOf("x.address==a") < step.argv[2].indexOf("v.move"))
  }

  for (const address of malicious.invalidAddresses) {
    const invalid = { ...hidden, address }
    assert.equal(Transaction.restoreMoveStep(invalid, "7"), null)
    assert.equal(Transaction.postRestoreStep(invalid, "7", true), null)
    assert.equal(Transaction.cleanupStep(invalid, "7"), null)
    assert.equal(Transaction.ensureHiddenOverrideStep(invalid), null)
  }
  for (const target of malicious.invalidWorkspaces) {
    assert.equal(Transaction.restoreMoveStep(hidden, target), null)
    assert.equal(Transaction.postRestoreStep(hidden, target, true), null)
    assert.equal(Transaction.cleanupStep(hidden, target), null)
    assert.equal(Transaction.resolveRestoreStep(hidden, target), null)
  }
})

test("all maximum-size guarded repl requests fit Hyprland's safe frame", () => {
  const longName = "name:" + "x".repeat(127)
  const record = {
    ...recordFor(clients.normal),
    address: "0x" + "f".repeat(16),
    pid: 2147483647,
    compositorStableId: "f".repeat(16),
    origin: longName,
    sourceWorkspace: "special:scratchpad"
  }
  const steps = [
    Transaction.minimizeStep(record, "special:minimum"),
    Transaction.restoreMoveStep(record, longName),
    Transaction.postRestoreStep(record, longName, true),
    Transaction.cleanupStep(record, longName),
    Transaction.ensureHiddenOverrideStep(record),
    Transaction.rollbackMinimizeStep(record, "special:minimum"),
    Transaction.resolveMinimizeStep(record, "special:minimum"),
    Transaction.resolveRestoreStep(record, longName)
  ]
  assert.ok(steps.every(Boolean))
  assert.ok(steps.every((step) => step.argv[2].length <= 1016))
  assert.ok(steps.every((step) => !step.argv[2].includes("\n")))
})
