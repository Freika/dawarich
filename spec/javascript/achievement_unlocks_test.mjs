import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL("../../app/javascript/controllers/achievement_unlocks_controller.js", import.meta.url),
    "utf8",
  )
).replace(/^import .*\n/gm, "")
const { default: UnlocksController } = await import(
  `data:text/javascript;base64,${Buffer.from(`class Controller {}\n${source}`).toString("base64")}`
)

function fixture(t, responses = []) {
  const calls = []
  const storage = new Map()
  const globals = {
    document: {
      hidden: false,
      modalOpen: false,
      querySelector(selector) {
        if (selector === "dialog[open]") return this.modalOpen ? {} : null
        return { content: "csrf-token" }
      },
    },
    sessionStorage: {
      getItem: (key) => storage.get(key) || null,
      setItem: (key, value) => storage.set(key, value),
      removeItem: (key) => storage.delete(key),
    },
    matchMedia: () => ({ matches: false }),
    fetch: async (url, options) => {
      calls.push({ url, body: JSON.parse(options.body) })
      return responses.shift()
    },
  }
  for (const [key, value] of Object.entries(globals)) {
    const original = Object.getOwnPropertyDescriptor(globalThis, key)
    Object.defineProperty(globalThis, key, { configurable: true, value })
    t.after(() => {
      if (original) Object.defineProperty(globalThis, key, original)
      else delete globalThis[key]
    })
  }

  const element = {
    firstElementChild: null,
    set innerHTML(value) {
      this.html = value
      this.firstElementChild = value ? { classList: { add() {} } } : null
    },
    get innerHTML() { return this.html || "" },
    replaceChildren() { this.innerHTML = "" },
  }
  const controller = new UnlocksController()
  controller.element = element
  controller.nextUrlValue = "/achievements/unlocks/next"
  controller.seenUrlValue = "/achievements/unlocks/__ID__/seen"
  controller.dismissUrlValue = "/achievements/unlocks/dismiss"
  controller.userIdValue = 42
  controller.storageKey = "dawarich-achievement-unlock-claim-42"
  controller.generation = 1
  controller.stopped = false
  t.after(() => controller.disconnect())
  return { controller, element, calls, storage, document: globals.document }
}

function response(status, payload) {
  return { status, ok: status >= 200 && status < 300, json: async () => payload }
}

test("shows one card at a time, acknowledges it, and advances the deck", async (t) => {
  const { controller, element, calls, storage } = fixture(t, [
    response(200, { id: 7, token: "a", batch_end_id: 8, remaining: 2, html: "<section>France</section>" }),
    response(204),
    response(200, { id: 8, token: "b", batch_end_id: 8, remaining: 1, html: "<section>Germany</section>" }),
    response(204),
  ])

  await controller.load()
  clearTimeout(controller.ackTimer)
  assert.match(element.innerHTML, /France/)
  assert.equal(storage.size, 1)
  await controller.nextCard()
  clearTimeout(controller.ackTimer)
  assert.match(element.innerHTML, /Germany/)
  assert.deepEqual(calls.map((call) => call.url), [
    "/achievements/unlocks/next",
    "/achievements/unlocks/7/seen",
    "/achievements/unlocks/next",
  ])
  assert.equal(calls[2].body.batch_end_id, 8)
  await controller.nextCard()
  assert.equal(element.innerHTML, "")
  assert.equal(storage.size, 0)
})

test("waits while another dialog obscures the card", async (t) => {
  const { controller, calls, document } = fixture(t)
  document.modalOpen = true

  await controller.load()

  assert.equal(calls.length, 0)
  clearTimeout(controller.retryTimer)
})

test("checks the inbox when an open browser tab is revisited", async (t) => {
  const { controller, calls, document, element } = fixture(t, [
    response(204),
    response(200, { id: 9, token: "c", batch_end_id: 9, remaining: 1, html: "<section>Poland</section>" }),
  ])

  await controller.load()
  document.hidden = true
  await controller.resumeVisit()
  assert.equal(calls.length, 1)

  document.hidden = false
  await controller.resumeVisit()
  clearTimeout(controller.ackTimer)
  assert.equal(calls.length, 2)
  assert.match(element.innerHTML, /Poland/)
})

test("dismisses the original batch without fetching every card", async (t) => {
  const { controller, calls, element } = fixture(t, [
    response(200, { id: 7, token: "a", batch_end_id: 100, remaining: 120, html: "<section>France</section>" }),
    response(204),
  ])
  await controller.load()
  clearTimeout(controller.ackTimer)

  await controller.dismiss()

  assert.equal(calls.length, 2)
  assert.equal(calls[1].body.batch_end_id, 100)
  assert.equal(element.innerHTML, "")
})
