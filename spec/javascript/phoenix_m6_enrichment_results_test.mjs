import assert from "node:assert/strict"
import test from "node:test"
import { createEnrichmentResults } from "../../app-phoenix/assets/js/map/ui/enrichment_results.js"
import { Element } from "./support/native_m6_host_fixture.mjs"

function fixture(options = {}) {
  const host = new Element(),
    list = new Element(),
    all = new Element(),
    submit = new Element(),
    status = new Element()
  host.dataset.labels = JSON.stringify({
    enrich_photos: "Enrich {count}",
    confirm_enrich: "Confirm {count}",
    enriching: "Pending {count}",
    pending_enrichment: "Submitted {count}",
    failed: "Failed",
  })
  const nodes = new Map([
    ["[data-enrichment-list]", list],
    ["[data-enrichment-all]", all],
    ["[data-enrichment-submit]", submit],
    ["[data-enrichment-status]", status],
  ])
  host.querySelector = (selector) => nodes.get(selector)
  const root = {
    querySelector: () => host,
    ownerDocument: { createElement: () => new Element() },
  }
  const jobs = new Map(),
    commands = []
  let next = 0
  const owner = createEnrichmentResults({
    ...options,
    root,
    timers: {
      setTimeout(fn, delay) {
        jobs.set(++next, { fn, delay })
        return next
      },
      clearTimeout(id) {
        jobs.delete(id)
      },
    },
    pushEvent(event, payload, reply) {
      commands.push({ event, payload, reply })
    },
    confirm: () => true,
  })
  return { owner, jobs, commands, list, all, submit, status }
}
const rows = [{ immich_asset_id: "one", latitude: 52, longitude: 13 }]

test("timed out enrichment attempt cannot settle its same-result retry or cancel that retry deadline", () => {
  const f = fixture()
  try {
    f.owner.replace(rows)
    f.submit.emit("click")
    const first = f.commands[0]
    const deadlineA = [...f.jobs.values()][0]
    assert.equal(deadlineA.delay, 60000)
    deadlineA.fn()
    assert.equal(f.submit.disabled, false)
    f.submit.emit("click")
    const deadlineB = [...f.jobs.values()][0]
    assert.equal(f.status.textContent, "Pending 1")
    first.reply({ ok: true, result: { pending: 99 } })
    assert.equal(f.status.textContent, "Pending 1")
    assert.equal(f.submit.disabled, true)
    assert.equal(f.all.disabled, true)
    assert.equal([...f.jobs.values()][0], deadlineB)
    deadlineA.fn()
    assert.equal([...f.jobs.values()][0], deadlineB)
    f.commands[1].reply({ error: "refused" })
    assert.equal(f.status.textContent, "Failed")
    assert.equal(f.submit.disabled, false)
    assert.equal(f.jobs.size, 0)
  } finally {
    f.owner.destroy()
  }
})

test("closing or replacing enrichment popups aborts only their thumbnails and revokes every popup URL", async () => {
  const requests = [],
    popups = [],
    active = new Set()
  let serial = 0
  class Popup {
    constructor() {
      popups.push(this)
      this.listeners = new Map()
    }
    setLngLat() {
      return this
    }
    setDOMContent(content) {
      this.content = content
      return this
    }
    addTo() {
      return this
    }
    on(event, fn) {
      this.listeners.set(event, fn)
      return this
    }
    off(event) {
      this.listeners.delete(event)
      return this
    }
    remove() {
      this.removed = true
      this.listeners.get("close")?.()
    }
  }
  const f = fixture({
    map: {},
    library: { Popup },
    reader: {
      read(_resource, _params, { signal }) {
        return new Promise((resolve) => requests.push({ signal, resolve }))
      },
    },
    urls: {
      createObjectURL() {
        const url = `blob:${++serial}`
        active.add(url)
        return url
      },
      revokeObjectURL(url) {
        active.delete(url)
      },
    },
  })
  const drain = () => new Promise((resolve) => setImmediate(resolve))
  try {
    f.owner.replace(rows)
    requests[0].resolve({ data: new Blob(["row"]) })
    await drain()
    assert.equal(active.size, 1)
    f.list.children[0].emit("mouseenter")
    const late = requests[1]
    f.list.children[0].emit("mouseleave")
    assert.equal(late.signal.aborted, true)
    assert.equal(popups[0].removed, true)
    late.resolve({ data: new Blob(["closed"]) })
    await drain()
    assert.equal(active.size, 1)
    for (let index = 0; index < 3; index++) {
      f.owner.showPopup("one")
      requests.at(-1).resolve({ data: new Blob(["current"]) })
      await drain()
      assert.equal(active.size, 2)
    }
    assert.equal(
      popups.slice(0, -1).every((popup) => popup.removed),
      true,
    )
    popups.at(-1).listeners.get("close")()
    assert.equal(active.size, 1)
    assert.equal(requests[0].signal.aborted, false)
  } finally {
    f.owner.destroy()
  }
  assert.equal(active.size, 0)
})
