import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

const root = new URL("../../", import.meta.url)
const controls = await readFile(new URL("lib/dawarich_web/features/families/components/family_native_controls.ex", root), "utf8")
const confirmation = await readFile(new URL("lib/dawarich_web/native_family_confirmation.ex", root), "utf8")
const hookSource = await readFile(new URL("assets/js/hooks/family_confirm.js", root), "utf8")
const { FamilyConfirm } = vm.runInNewContext(hookSource.replace("export const FamilyConfirm =", "const FamilyConfirm =") + "\n;({ FamilyConfirm })")

function dialog() {
  const listeners = new Map()
  const commands = []
  const el = {
    open: true,
    dataset: { pending: "true" },
    addEventListener: (name, fn) => listeners.set(name, fn),
    removeEventListener: (name, fn) => {
      assert.equal(listeners.get(name), fn)
      listeners.delete(name)
    },
    close() {
      this.open = false
      listeners.get("close")?.()
    },
  }
  const hook = { ...FamilyConfirm, el, pushEvent: (name) => commands.push(name) }
  hook.mounted()
  return { hook, el, listeners, commands }
}

test("native family cancelled member deletion and invitation confirmations dispatch no command", () => {
  assert.match(controls, /JS\.push\("family_prepare_confirm"/)
  assert.match(confirmation, /confirmation: nil.*socket\),\s*do: \{:noreply, socket\}/s)
  for (const mode of ["escape", "close", "cancel-button"]) {
    const { hook, el, listeners, commands } = dialog()
    let prevented = false
    if (mode === "escape") listeners.get("cancel")({ preventDefault() { prevented = true } })
    if (mode === "close") el.close()
    if (mode === "cancel-button") {
      assert.match(controls, /JS\.push\("family_cancel_confirm"\)/)
      commands.push("family_cancel_confirm")
      el.dataset.pending = "false"
      hook.updated()
    }
    assert.deepEqual(commands, ["family_cancel_confirm"])
    assert.equal(el.open, false)
    assert.equal(prevented, mode === "escape")
    hook.destroyed()
    assert.equal(listeners.size, 0)
  }
})

test("native family accepted member deletion and invitation confirmations dispatch one command", () => {
  const command = controls.match(/phx-click="(family_confirm)"/)?.[1]
  assert.equal(command, "family_confirm")
  for (const action of ["remove_member", "delete", "cancel_invitation"]) {
    assert.match(confirmation, new RegExp(`"${action}" ->`))
    const { hook, el, commands, listeners } = dialog()
    commands.push(command)
    el.dataset.pending = "false"
    hook.updated()
    assert.deepEqual(commands, ["family_confirm"])
    assert.equal(el.open, false)
    hook.destroyed()
    assert.equal(listeners.size, 0)
  }
})
