import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

// CI runs Node 18, whose test runner has no fake timers: a minimal manual clock.
function fakeTimeouts(t) {
  const realSetTimeout = globalThis.setTimeout
  const realClearTimeout = globalThis.clearTimeout
  const pending = new Map()
  let now = 0
  let nextId = 1
  globalThis.setTimeout = (callback, delay = 0) => {
    const id = nextId++
    pending.set(id, { at: now + delay, callback })
    return id
  }
  globalThis.clearTimeout = (id) => pending.delete(id)
  t.after(() => {
    globalThis.setTimeout = realSetTimeout
    globalThis.clearTimeout = realClearTimeout
  })
  return {
    tick(ms) {
      const until = now + ms
      for (;;) {
        const due = [...pending]
          .filter(([, timer]) => timer.at <= until)
          .sort((a, b) => a[1].at - b[1].at)[0]
        if (!due) break
        pending.delete(due[0])
        now = due[1].at
        due[1].callback()
      }
      now = until
    },
  }
}

async function controller(path) {
  const source = await readFile(
    new URL(`../../app/javascript/controllers/${path}`, import.meta.url),
    "utf8",
  )
  const names = []
  const body = source.replace(
    /^import\s+([\s\S]*?)\s+from\s+"[^"]+"\n/gm,
    (_, clause) => {
      if (clause.includes("* as")) names.push(clause.split("* as")[1].trim())
      else {
        for (const part of (clause.match(/\{([\s\S]*)\}/)?.[1] || "").split(
          ",",
        )) {
          const name = part
            .trim()
            .split(/\s+as\s+/)
            .pop()
          if (name) names.push(name)
        }
        const name = clause
          .replace(/\{[\s\S]*\}/, "")
          .replace(",", "")
          .trim()
        if (name) names.push(name)
      }
      return ""
    },
  )
  const stubs = names
    .map((name) =>
      name === "Controller"
        ? "class Controller {}"
        : `const ${name} = globalThis.uxP3Stubs?.${name} ?? (() => {})`,
    )
    .join("\n")
  return (
    await import(
      `data:text/javascript;base64,${Buffer.from(`${stubs}\n${body}`).toString("base64")}`
    )
  ).default
}
const toasts = []
globalThis.uxP3Stubs = {
  translate: (key, values = {}) =>
    `${key}:${values.count ?? ""}/${values.total ?? ""}`,
  Toast: {
    success: (value) => toasts.push(value),
    warning: (value) => toasts.push(value),
  },
}
const Timeline = await controller("timeline_feed_controller.js")
const Realtime = await controller("maps/maplibre_realtime_controller.js")
const Video = await controller("video_studio_controller.js")
function classList(initial = []) {
  const set = new Set(initial)
  return {
    contains: (name) => set.has(name),
    add: (name) => set.add(name),
    remove: (name) => set.delete(name),
    replace(a, b) {
      if (set.delete(a)) set.add(b)
    },
    toggle(name, force) {
      const on = force ?? !set.has(name)
      on ? set.add(name) : set.delete(name)
      return on
    },
  }
}
function timeline() {
  const rows = ["café süd", "park", "library"].map((searchTokens) => ({
    dataset: { searchTokens, status: "confirmed" },
    classList: classList(),
  }))
  const count = { textContent: "3 visits" },
    scope = { classList: classList(["hidden"]) },
    empty = { classList: classList(["hidden"]) }
  const day = {
    classList: classList(),
    querySelectorAll: () => rows,
    querySelector: (key) =>
      key.includes("visit-count")
        ? count
        : key.includes("filter-scope")
          ? scope
          : empty,
  }
  const ctl = Object.create(Timeline.prototype)
  Object.assign(ctl, {
    hasVisitListFrameTarget: true,
    visitListFrameTarget: { querySelectorAll: () => [day] },
    readFilterDetail: () => ({}),
    readSearchQuery: () => "",
    readActiveTags: () => [],
  })
  return { ctl, rows, day, count, scope, empty }
}
test("timeline counts one and zero matches, explains scope and restores the full list", () => {
  const { ctl, count, scope, empty, rows } = timeline()
  ctl.readSearchQuery = () => "café"
  ctl.applyVisibility()
  assert.equal(count.textContent, "ux_p3.timeline.filtered_count:1/3")
  assert.equal(scope.classList.contains("hidden"), false)
  assert.equal(
    rows.filter((row) => !row.classList.contains("visit-row--hidden")).length,
    1,
  )
  ctl.readSearchQuery = () => "missing"
  ctl.applyVisibility()
  assert.equal(count.textContent, "ux_p3.timeline.filtered_count:0/3")
  assert.equal(empty.classList.contains("hidden"), false)
  ctl.readSearchQuery = () => ""
  ctl.applyVisibility()
  assert.equal(count.textContent, "ux_p3.timeline.visit_count:3/3")
  assert.equal(scope.classList.contains("hidden"), true)
})
test("timeline excludes collapsed low confidence stops but searches them", () => {
  const { ctl, rows, count, day } = timeline()
  rows[0].classList.add("visit-row--lowconf")
  ctl.applyVisibility()
  assert.equal(count.textContent, "ux_p3.timeline.filtered_count:2/3")
  ctl.readSearchQuery = () => "café"
  ctl.applyVisibility()
  assert.equal(count.textContent, "ux_p3.timeline.filtered_count:1/3")
  assert.equal(day.classList.contains("timeline-day--filtering"), true)
})
test("timeline tag and status filters contribute to the same result count", () => {
  const { ctl, rows, count } = timeline()
  rows[0].dataset.searchTokens += " #home"
  ctl.readActiveTags = () => ["#home"]
  ctl.applyVisibility()
  assert.equal(count.textContent, "ux_p3.timeline.filtered_count:1/3")
  ctl.readFilterDetail = () => ({ confirmed: false })
  ctl.applyVisibility()
  assert.equal(count.textContent, "ux_p3.timeline.filtered_count:0/3")
})
test("realtime is quiet for initial connect and transient disconnect, and cancels stale timers", (t) => {
  const timers = fakeTimeouts(t)
  const ctl = Object.create(Realtime.prototype)
  const states = []
  Object.assign(ctl, {
    connectedChannels: new Set(),
    updateConnectionIndicator: (value) => states.push(value),
  })
  ctl.handleConnected("tracks")
  ctl.handleDisconnected("tracks")
  timers.tick(9999)
  assert.deepEqual(states, [true])
  ctl.handleConnected("tracks")
  timers.tick(1)
  assert.deepEqual(states, [true, true])
  assert.deepEqual(toasts, [])
})
test("sustained disconnect shows an inline problem once, then reconnect clears it", (t) => {
  const timers = fakeTimeouts(t)
  const ctl = Object.create(Realtime.prototype)
  const states = []
  Object.assign(ctl, {
    connectedChannels: new Set(["tracks", "family"]),
    updateConnectionIndicator: (value) => states.push(value),
  })
  ctl.handleDisconnected("tracks")
  timers.tick(10000)
  assert.deepEqual(states, [])
  ctl.handleDisconnected("family")
  ctl.handleDisconnected("family")
  timers.tick(10000)
  assert.deepEqual(states, [false])
  ctl.handleConnected("tracks")
  assert.deepEqual(states, [false, true])
  assert.deepEqual(toasts, [])
})
test("leaving the map cancels connection setup and delayed warnings", (t) => {
  const timers = fakeTimeouts(t)
  const ctl = Object.create(Realtime.prototype)
  Object.assign(ctl, {
    connectedChannels: new Set(),
    updateConnectionIndicator: () => assert.fail("stale warning"),
  })
  ctl.handleDisconnected("tracks")
  ctl.channelSetupTimer = setTimeout(() => assert.fail("stale setup"), 1000)
  ctl.disconnect()
  timers.tick(15000)
})
test("completed MP4 has a primary named download and clearing the result removes stale access", () => {
  const ctl = Object.create(Video.prototype)
  const element = () => ({
    classList: classList(["hidden"]),
    removeAttribute(key) {
      delete this[key]
    },
  })
  Object.assign(ctl, {
    downloadButtonTarget: element(),
    renderButtonTarget: element(),
    resultTarget: element(),
    saveButtonTarget: { disabled: true, classList: classList(["hidden"]) },
    nameInputTarget: { value: "Berlin / Café" },
    statusTarget: {},
    hideHudPreview() {},
    drawHudPreview() {},
    showProgress() {},
  })
  ctl.renderButtonTarget.classList.add("btn-primary")
  ctl.showResult(new Blob(["synthetic mp4"], { type: "video/mp4" }))
  const firstUrl = ctl.resultUrl
  assert.match(ctl.downloadButtonTarget.href, /^blob:/)
  assert.equal(ctl.downloadButtonTarget.download, "Berlin  Café.mp4")
  assert.equal(ctl.downloadButtonTarget.classList.contains("hidden"), false)
  assert.equal(ctl.renderButtonTarget.classList.contains("btn-primary"), false)
  ctl.clearResult()
  assert.equal(ctl.downloadButtonTarget.href, undefined)
  assert.equal(ctl.downloadButtonTarget.classList.contains("hidden"), true)
  assert.equal(ctl.renderButtonTarget.classList.contains("btn-primary"), true)
  assert.equal(ctl.resultUrl, null)
  assert.equal(ctl.blob, null)
  assert.notEqual(firstUrl, null)
})
