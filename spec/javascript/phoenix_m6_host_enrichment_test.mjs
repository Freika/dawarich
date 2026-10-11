import assert from "node:assert/strict"
import test from "node:test"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

test("native host owns enrichment marker replies and removes them on range replacement", async () => {
  const f = fixture()
  await f.owner.mount()
  f.owner.enrichment.matches({
    matches: [{ immich_asset_id: "synthetic", latitude: 52, longitude: 13 }],
  })
  assert.equal(
    f.sources.get("native-enrichment-matches").data.features.length,
    1,
  )
  await f.owner.update({ ...f.owner.config, revision: 2 })
  assert.equal(f.sources.has("native-enrichment-matches"), false)
  f.owner.destroy()
})

function resultUI(f) {
  const result = new Element(),
    list = new Element(),
    all = new Element(),
    submit = new Element(),
    status = new Element()
  result.dataset.labels = JSON.stringify({
    enrich_photos: "Enrich {count} photos",
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
  result.querySelector = (selector) => nodes.get(selector)
  f.nodes.set("[data-enrichment-results]", result)
  return { result, list, all, submit, status }
}

const rows = [
  { immich_asset_id: "one", filename: "<photo>", latitude: 52, longitude: 13 },
  { immich_asset_id: "two", filename: "other", latitude: 53, longitude: 14 },
]

test("native enrichment selection confirms and sends only selected assets with pending feedback", async () => {
  const f = fixture(),
    ui = resultUI(f)
  const confirms = []
  const original = globalThis.confirm
  globalThis.confirm = (message) => {
    confirms.push(message)
    return true
  }
  try {
    await f.owner.mount()
    await f.owner.enrichment.matches({ matches: rows })
    assert.equal(ui.list.children.length, 2)
    ui.all.checked = false
    ui.all.emit("change")
    assert.equal(ui.submit.disabled, true)
    const checkbox = ui.list.children[0].children[0]
    checkbox.checked = true
    checkbox.emit("change")
    ui.submit.emit("click")
    const command = f.pushed.find(
      (event) => event.event === "enrichment:enrich",
    )
    assert.deepEqual(command.payload.assets, [
      { immich_asset_id: "one", latitude: 52, longitude: 13 },
    ])
    assert.equal(confirms.length, 1)
    assert.equal(ui.submit.disabled, true)
    assert.match(ui.status.textContent, /Pending 1/)
    command.reply({ ok: true, result: { pending: 1, failed: 0 } })
    assert.match(ui.status.textContent, /Submitted 1/)
    assert.equal(ui.submit.disabled, true)
    assert.equal(ui.list.children.length, 0)
  } finally {
    globalThis.confirm = original
    f.owner.destroy()
  }
})

test("native enrichment confirmation refusal failure and teardown cannot apply obsolete results", async () => {
  const f = fixture(),
    ui = resultUI(f)
  const original = globalThis.confirm
  globalThis.confirm = () => false
  try {
    await f.owner.mount()
    await f.owner.enrichment.matches({ matches: rows })
    ui.submit.emit("click")
    assert.equal(
      f.pushed.some((event) => event.event === "enrichment:enrich"),
      false,
    )
    globalThis.confirm = () => true
    ui.submit.emit("click")
    const command = f.pushed.find(
      (event) => event.event === "enrichment:enrich",
    )
    command.reply({ error: "pro_required" })
    assert.equal(ui.status.textContent, "Failed")
    assert.equal(ui.submit.disabled, false)
    ui.submit.emit("click")
    const late = f.pushed.at(-1)
    await f.owner.update({ ...f.owner.config, revision: 2 })
    assert.equal(ui.list.children.length, 0)
    await f.owner.enrichment.matches({ matches: [rows[0]] })
    ui.submit.emit("click")
    late.reply({ ok: true, result: { pending: 2 } })
    assert.equal(ui.status.textContent, "Pending 1")
    f.owner.destroy()
    await f.owner.enrichment.matches({ matches: rows })
    ui.submit.emit("click")
    assert.equal(ui.list.children.length, 0)
    assert.equal(
      f.pushed.filter((event) => event.event === "enrichment:enrich").length,
      3,
    )
  } finally {
    globalThis.confirm = original
    f.owner.destroy()
  }
})

test("enrichment thumbnails popups and pending reads are released on range change and destroy", async () => {
  const popups = []
  class Popup {
    constructor() {
      popups.push(this)
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
    remove() {
      this.removed = true
    }
  }
  const f = fixture({}, { library: { Popup } }),
    ui = resultUI(f)
  const originalCreate = URL.createObjectURL,
    originalRevoke = URL.revokeObjectURL
  const active = new Set(),
    requests = []
  URL.createObjectURL = () => {
    const url = `blob:${active.size}`
    active.add(url)
    return url
  }
  URL.revokeObjectURL = (url) => active.delete(url)
  f.reader.read = async (_resource, _params, options) => {
    requests.push(options)
    return { data: new Blob(["photo"]) }
  }
  try {
    await f.owner.mount()
    await f.owner.enrichment.matches({ matches: [rows[0]] })
    await new Promise((resolve) => setImmediate(resolve))
    assert.equal(active.size, 1)
    f.map.emit("mouseenter:native-enrichment-matches", {
      features: [{ properties: { id: "one" } }],
    })
    await new Promise((resolve) => setImmediate(resolve))
    assert.equal(popups.length, 1)
    assert.equal(popups[0].content.children[1].textContent, "<photo>")
    await f.owner.update({ ...f.owner.config, revision: 2 })
    assert.equal(popups[0].removed, true)
    assert.equal(active.size, 0)
    let release
    f.reader.read = (_resource, _params, options) => {
      requests.push(options)
      return new Promise((resolve) => {
        release = resolve
      })
    }
    await f.owner.enrichment.matches({ matches: [rows[0]] })
    f.owner.destroy()
    assert.equal(requests.at(-1).signal.aborted, true)
    release({ data: new Blob(["late"]) })
    await new Promise((resolve) => setImmediate(resolve))
    assert.equal(active.size, 0)
    assert.equal(ui.list.children.length, 0)
  } finally {
    f.owner.destroy()
    URL.createObjectURL = originalCreate
    URL.revokeObjectURL = originalRevoke
  }
})

test("enrichment results bind when the tools panel appears after map attachment", async () => {
  const f = fixture()
  try {
    await f.owner.mount()
    const ui = resultUI(f)
    await f.owner.enrichment.matches({ matches: rows })
    assert.equal(ui.list.children.length, 2)
    ui.all.checked = false
    ui.all.emit("change")
    assert.equal(ui.submit.disabled, true)
  } finally {
    f.owner.destroy()
  }
})

test("accepted enrichment retires selection markers and popups until a new scan while keeping its receipt", async () => {
  const popups = []
  class Popup {
    constructor() {
      popups.push(this)
    }
    setLngLat() {
      return this
    }
    setDOMContent() {
      return this
    }
    addTo() {
      return this
    }
    remove() {
      this.removed = true
    }
  }
  const f = fixture({}, { library: { Popup } }),
    ui = resultUI(f)
  const original = globalThis.confirm
  globalThis.confirm = () => true
  ui.result.dataset.labels = JSON.stringify({
    ...JSON.parse(ui.result.dataset.labels),
    partially_enriched: "Partial {enriched}/{failed}",
    enriched: "Enriched {count}",
  })
  try {
    await f.owner.mount()
    for (const [result, receipt] of [
      [{ pending: 1, failed: 0 }, "Submitted 1"],
      [{ enriched: 1, failed: 1 }, "Partial 1/1"],
      [{ enriched: 1, failed: 0 }, "Enriched 1"],
    ]) {
      await f.owner.enrichment.matches({ matches: rows })
      ui.list.children[1].children[0].checked = false
      ui.list.children[1].children[0].emit("change")
      ui.list.children[0].emit("mouseenter")
      ui.submit.emit("click")
      const command = f.pushed.at(-1)
      assert.equal(command.payload.assets.length, 1)
      command.reply({ ok: true, result })
      assert.equal(ui.status.textContent, receipt)
      assert.equal(ui.list.children.length, 0)
      assert.equal(ui.all.checked, false)
      assert.equal(ui.submit.disabled, true)
      assert.equal(f.sources.has("native-enrichment-matches"), false)
      assert.equal(f.layers.has("native-enrichment-matches"), false)
      assert.equal(popups.at(-1).removed, true)
      const count = f.pushed.length
      ui.submit.emit("click")
      assert.equal(f.pushed.length, count)
    }
  } finally {
    globalThis.confirm = original
    f.owner.destroy()
  }
})
