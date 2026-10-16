import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"
import { createYearMap } from "../../assets/js/insights/year_map.js"

test("lazy year previews cancel pending reads release maps and unwrap antimeridian lines", async () => {
  let visibility,
    removed = 0,
    disconnected = 0,
    sources = [],
    requested = 0
  const element = { dataset: { url: "/insights/routes/2025" }, hidden: false }
  const observe = (_, callback) => {
    visibility = callback
    return () => disconnected++
  }
  class FakeMap {
    isStyleLoaded() {
      return true
    }
    addSource(_, data) {
      sources.push(data.data.geometry.coordinates)
    }
    addLayer() {}
    fitBounds() {}
    remove() {
      removed++
    }
  }
  class Bounds {
    extend() {}
    isEmpty() {
      return false
    }
  }
  const opts = {
    observe,
    loadLibrary: async () => ({ Map: FakeMap, LngLatBounds: Bounds }),
    loadStyle: async () => ({}),
    fetch: async () => {
      requested++
      return {
        ok: true,
        json: async () => ({
          lines: [
            [
              [179, 1],
              [-179, 2],
            ],
          ],
        }),
      }
    },
  }
  const owner = createYearMap(element, opts)
  assert.equal(requested, 0)
  await visibility(true)
  assert.equal(requested, 1)
  assert.ok(
    sources[0].every((line) =>
      line.every((p, i, a) => !i || Math.abs(p[0] - a[i - 1][0]) < 180),
    ),
  )
  owner.destroy()
  assert.equal(removed, 1)
  assert.equal(disconnected, 1)
  let finish, signal
  const pending = createYearMap(element, {
    ...opts,
    fetch: (_, o) => {
      signal = o.signal
      return new Promise((resolve) => {
        finish = resolve
      })
    },
  })
  const work = visibility(true)
  pending.destroy()
  assert.equal(signal.aborted, true)
  finish({
    ok: true,
    json: async () => ({
      lines: [
        [
          [1, 1],
          [2, 2],
        ],
      ],
    }),
  })
  await work
  assert.equal(removed, 1)
  const empty = createYearMap(element, {
    ...opts,
    fetch: async () => ({ ok: true, json: async () => ({ lines: [] }) }),
  })
  await visibility(true)
  assert.equal(element.hidden, true)
  empty.destroy()
})

test("the shared hook registry exposes the lazy InsightsYearMap owner", () => {
  const source = readFileSync(
    new URL("../../assets/js/hooks/index.js", import.meta.url),
    "utf8",
  )
  const bindings = {}
  for (const match of source.matchAll(
    /import\s*{([^}]+)}\s*from\s*["'][^"']+["']/g,
  )) {
    for (const item of match[1].split(",")) {
      const name = item
        .trim()
        .split(/\s+as\s+/)
        .at(-1)
      if (name) bindings[name] = { name }
    }
  }
  const registry = source
    .replace(/import\s*{[^}]+}\s*from\s*["'][^"']+["']/g, "")
    .replace("export const hooks", "globalThis.hooks")
  const context = vm.createContext(bindings)
  vm.runInContext(registry, context)
  assert.equal(context.hooks.InsightsYearMap, bindings.InsightsYearMap)
  assert.ok(context.hooks.InsightsYearMap)
  const hook = readFileSync(
    new URL("../../assets/js/insights/year_map_hook.js", import.meta.url),
    "utf8",
  )
  assert.match(hook, /await import\("\.\/year_map\.js"\)/)
})
