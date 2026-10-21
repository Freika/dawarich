import assert from "node:assert/strict"
import test from "node:test"
import { bindTool } from "../../app-phoenix/assets/js/map/ui/host_tools.js"

test("native tool clicks survive a replaced launcher and expire with their root", () => {
  class Root extends EventTarget {
    constructor() {
      super()
      this.button = null
    }
    querySelector() {
      return this.button
    }
    contains(button) {
      return button.root === this
    }
  }
  class Button extends EventTarget {
    constructor(root) {
      super()
      this.root = root
    }
    closest(selector) {
      return selector === "[data-native-map-root]" ? this.root : this
    }
    click(root = this.root) {
      this.dispatchEvent(new Event("click"))
      const event = new Event("click")
      Object.defineProperty(event, "target", { value: this })
      root.dispatchEvent(event)
    }
  }
  const root = new Root(),
    cleanups = []
  root.button = new Button(root)
  let calls = 0
  bindTool(root, "[data-testid=native-create-visit]", () => calls++, {
    own: (cleanup) => cleanups.push(cleanup),
  })
  root.button.click()
  assert.equal(calls, 1)
  root.button = new Button(root)
  root.button.click()
  assert.equal(calls, 2)
  new Button(new Root()).click(root)
  assert.equal(calls, 2)
  cleanups.forEach((cleanup) => {
    cleanup()
  })
  root.button.click()
  assert.equal(calls, 2)
})
