import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

const entry = await readFile(new URL("../../assets/js/app.js", import.meta.url), "utf8")
const pages = await Promise.all(
  ["native_family_page", "native_family_invitations"].map((name) =>
    readFile(new URL(`../../lib/dawarich_web/components/${name}.ex`, import.meta.url), "utf8"),
  ),
)
const html = await readFile(
  new URL("../../deps/phoenix_html/priv/static/phoenix_html.js", import.meta.url),
  "utf8",
)

function click(action, decision) {
  assert.match(entry, /import "phoenix_html"/)
  const button = pages.join("\n").match(
    new RegExp(`<button\\b[^>]*phx-click="family:${action}"[^>]*>`, "s"),
  )?.[0]
  assert.match(button || "", /data-confirm=/)
  const listeners = new Map()
  let prompts = 0
  let commands = 0
  class Event {
    constructor(type) {
      this.type = type
      this.defaultPrevented = false
    }
    preventDefault() { this.defaultPrevented = true }
    stopImmediatePropagation() { this.stopped = true }
  }
  const window = {
    CustomEvent: Event,
    addEventListener(type, handler) {
      const handlers = listeners.get(type) || []
      handlers.push(handler)
      listeners.set(type, handlers)
    },
    confirm() { prompts += 1; return decision },
  }
  vm.runInNewContext(html, { window })
  window.addEventListener("click", () => { commands += 1 })
  const element = {
    getAttribute: (key) => key === "data-confirm" ? "Synthetic family confirmation" : null,
    dispatchEvent(event) {
      event.target = this
      for (const handler of listeners.get(event.type) || []) handler(event)
      return !event.defaultPrevented
    },
  }
  const event = new Event("click")
  event.target = element
  for (const handler of listeners.get("click")) {
    handler(event)
    if (event.stopped) break
  }
  return { prompts, commands }
}

test("native family cancelled member deletion and invitation confirmations dispatch no command", () => {
  for (const action of ["member", "destroy", "cancel"])
    assert.deepEqual(click(action, false), { prompts: 1, commands: 0 })
})

test("native family accepted member deletion and invitation confirmations dispatch one command", () => {
  for (const action of ["member", "destroy", "cancel"])
    assert.deepEqual(click(action, true), { prompts: 1, commands: 1 })
})
