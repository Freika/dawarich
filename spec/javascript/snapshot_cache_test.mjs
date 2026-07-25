import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/snapshot_cache.js",
    import.meta.url,
  ),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { CACHE_PREFIX, readCache, writeCache, evictOldest } = await import(
  moduleUrl
)

function fakeStore() {
  const map = new Map()
  return {
    get length() {
      return map.size
    },
    key(i) {
      return [...map.keys()][i] ?? null
    },
    getItem(k) {
      return map.has(k) ? map.get(k) : null
    },
    setItem(k, v) {
      map.set(k, v)
    },
    removeItem(k) {
      map.delete(k)
    },
  }
}

test("writeCache then readCache returns the value (cache hit)", () => {
  const store = fakeStore()
  const key = `${CACHE_PREFIX}1,2,3`

  writeCache(store, key, { img: "data:png", pin: { x: 1, y: 2 } }, 1000)
  const got = readCache(store, key)

  assert.equal(got.img, "data:png")
  assert.deepEqual(got.pin, { x: 1, y: 2 })
  assert.equal(got.t, 1000)
})

test("readCache returns null on a miss", () => {
  assert.equal(readCache(fakeStore(), `${CACHE_PREFIX}missing`), null)
})

test("readCache drops and null-returns a corrupt entry", () => {
  const store = fakeStore()
  const key = `${CACHE_PREFIX}bad`
  store.setItem(key, "{not json")

  assert.equal(readCache(store, key), null)
  assert.equal(store.getItem(key), null)
})

test("readCache/writeCache no-op when storage is unavailable", () => {
  assert.equal(readCache(null, "k"), null)
  assert.doesNotThrow(() => writeCache(null, "k", { img: "x" }, 1))
})

test("evictOldest drops the oldest quarter by timestamp", () => {
  const store = fakeStore()
  for (let i = 0; i < 8; i++) {
    writeCache(store, `${CACHE_PREFIX}k${i}`, { img: "x" }, i)
  }

  evictOldest(store)

  assert.equal(readCache(store, `${CACHE_PREFIX}k0`), null)
  assert.equal(readCache(store, `${CACHE_PREFIX}k1`), null)
  assert.ok(readCache(store, `${CACHE_PREFIX}k2`))
})

test("writeCache evicts then retries when the store is full", () => {
  const inner = fakeStore()
  const CAPACITY = 4
  const store = {
    get length() {
      return inner.length
    },
    key(i) {
      return inner.key(i)
    },
    getItem(k) {
      return inner.getItem(k)
    },
    removeItem(k) {
      inner.removeItem(k)
    },
    setItem(k, v) {
      if (inner.length >= CAPACITY) throw new Error("QuotaExceeded")
      inner.setItem(k, v)
    },
  }
  for (let i = 0; i < CAPACITY; i++) {
    inner.setItem(`${CACHE_PREFIX}k${i}`, JSON.stringify({ img: "x", t: i }))
  }

  writeCache(store, `${CACHE_PREFIX}new`, { img: "y" }, 99)

  assert.ok(readCache(store, `${CACHE_PREFIX}new`))
  assert.equal(readCache(store, `${CACHE_PREFIX}k0`), null) // oldest evicted
})
