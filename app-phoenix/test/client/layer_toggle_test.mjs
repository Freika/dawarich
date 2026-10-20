import assert from "node:assert/strict"
import test from "node:test"
import { LayerToggle } from "../../assets/js/hooks/layer_toggle.js"

class Input extends EventTarget {
  constructor(checked = true) {
    super()
    this.checked = checked
    this.dataset = { nativeChecked: String(checked) }
    this.attrs = new Map([["phx-click", "settings:layer"], ["phx-value-layer", "Points"]])
    this.toggleAttribute("checked", checked)
  }
  getAttribute(key) { return this.attrs.get(key) ?? null }
  toggleAttribute(key, value) { value ? this.attrs.set(key, "") : this.attrs.delete(key) }
  click() {
    this.checked = !this.checked
    this.dispatchEvent(new Event("click", { bubbles: true }))
  }
}

function fixture() {
  const sent = []
  const hook = { ...LayerToggle, el: new Input(), pushEvent: (...args) => sent.push(args) }
  hook.mounted()
  const patch = checked => {
    const incoming = new Input(checked)
    hook.beforeUpdate(incoming)
    hook.el.checked = incoming.checked
    hook.el.dataset = incoming.dataset
  }
  return { hook, sent, patch }
}

test("every layer click sends its browser checked value while earlier replies are pending", () => {
  const { hook, sent, patch } = fixture()
  hook.el.click()
  hook.el.click()
  assert.deepEqual(sent.map(([event, value]) => [event, value]), [
    ["settings:layer", { layer: "Points", enabled: false }],
    ["settings:layer", { layer: "Points", enabled: true }],
  ])
  patch(false)
  sent[0][2]()
  assert.equal(hook.el.checked, true)
  patch(true)
  sent[1][2]()
  assert.equal(hook.el.checked, true)
})

test("an earlier patch preserves the pending checkbox and the final reply restores server refusal", () => {
  const { hook, sent, patch } = fixture()
  hook.el.click()
  assert.equal(sent.length, 1)
  patch(true)
  assert.equal(hook.el.checked, false)
  assert.equal(hook.el.dataset.nativeChecked, "true")
  sent[0][2]()
  assert.equal(hook.el.checked, true)
  patch(false)
  assert.equal(hook.el.checked, false)
})

test("layer departure removes its listener and reconnect releases a pending browser choice", () => {
  const { hook, sent, patch } = fixture()
  hook.el.click()
  assert.equal(sent.length, 1)
  patch(true)
  hook.reconnected()
  assert.equal(hook.el.checked, true)
  hook.el.click()
  const count = sent.length
  hook.destroyed()
  hook.el.click()
  assert.equal(sent.length, count)
  const checked = hook.el.checked
  sent.at(-1)[2]()
  assert.equal(hook.el.checked, checked)
})
