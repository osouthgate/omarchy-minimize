#!/usr/bin/env node

const fs = require("node:fs")
const path = require("node:path")

function fail(message) {
  process.stderr.write(`live-smoke transaction helper: ${message}\n`)
  process.exit(2)
}

const pluginRoot = path.resolve(__dirname, "..", "..")
const source = fs.readFileSync(path.join(pluginRoot, "CompositorTransaction.js"), "utf8")
  .replace(/^\.pragma library\s*\r?\n/, "")
const moduleShim = { exports: {} }
Function("module", "exports", source)(moduleShim, moduleShim.exports)
const transaction = moduleShim.exports

const action = process.argv[2]
let record
try {
  record = JSON.parse(process.argv[3] || "")
} catch (_error) {
  fail("record must be valid JSON")
}
const target = process.argv[4]

if (action === "plan-restore") {
  const modelSource = fs.readFileSync(path.join(pluginRoot, "MinimizeModel.js"), "utf8")
    .replace(/^\.pragma library\s*\r?\n/, "")
  const modelShim = { exports: {} }
  Function("module", "exports", modelSource)(modelShim, modelShim.exports)
  let workspaces
  try {
    workspaces = JSON.parse(process.argv[5] || "[]")
  } catch (_error) {
    fail("workspaces must be valid JSON")
  }
  const plan = modelShim.exports.planRestore(record, target, true, workspaces)
  if (!plan || plan.ok !== true) fail("the production restore planner refused this request")
  process.stdout.write(JSON.stringify(plan))
  process.exit(0)
}

let step = null
if (action === "minimize")
  step = transaction.minimizeStep(record, target)
else if (action === "restore-move")
  step = transaction.restoreMoveStep(record, target)
else if (action === "post-restore")
  step = transaction.postRestoreStep(record, target, record.owned === true)
else if (action === "cleanup")
  step = transaction.cleanupStep(record, target)
else
  fail(`unsupported action: ${String(action)}`)

if (!step || !Array.isArray(step.argv) || step.argv[0] !== "hyprctl"
    || step.argv[1] !== "repl" || typeof step.argv[2] !== "string")
  fail("the production transaction builder refused this request")

process.stdout.write(step.argv[2])
