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
