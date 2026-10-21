import assert from "node:assert/strict"
import test from "node:test"
import { startLayerPreview } from "../../assets/js/map/ui/layer_gate.js"

test("Lite layer preview counts 20 15 10 5 and dismisses after twenty seconds", async t => {
  t.mock.timers.enable({ apis: ["setTimeout", "setInterval"] })
  const notices = [], toast = { parentNode: {}, textContent: "" }
  const toggle = { checked: true }
  let shown = 0, hidden = 0, ended = 0, dismissed = 0
  const cancel = await startLayerPreview({ layerName: "Heatmap", toggle, showFn: () => shown++, hideFn: () => hidden++, onEnd: () => ended++, translate: (key, values) => `${key}:${values.seconds}`, toast: { info: (text, duration) => { notices.push([text, duration]); return toast }, dismiss: () => dismissed++ } })
  assert.deepEqual(notices, [["layer_preview.started:20", 0]])
  assert.equal(shown, 1)
  t.mock.timers.tick(5000)
  assert.equal(toast.textContent, "layer_preview.remaining:15")
  t.mock.timers.tick(5000)
  assert.equal(toast.textContent, "layer_preview.remaining:10")
  t.mock.timers.tick(5000)
  assert.equal(toast.textContent, "layer_preview.remaining:5")
  t.mock.timers.tick(5000)
  assert.equal(hidden, 1)
  assert.equal(ended, 1)
  assert.equal(dismissed, 1)
  assert.equal(toggle.checked, false)
  cancel()
})
