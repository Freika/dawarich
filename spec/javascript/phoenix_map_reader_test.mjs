import assert from "node:assert/strict"
import { test } from "node:test"
import { createReader } from "../../app-phoenix/assets/js/map/data/reader.js"

const deferred = () => {
  let resolve
  const promise = new Promise((r) => {
    resolve = r
  })
  return { promise, resolve }
}
const response = (data, headers = {}, status = 200) =>
  new Response(JSON.stringify(data), { status, headers })

test("obsolete range fetch aborts and cannot commit", async () => {
  const pending = deferred()
  let requestSignal
  let commits = 0
  const reader = createReader({
    origin: "https://map.test",
    fetch: async (_, opts) => {
      requestSignal = opts.signal
      return pending.promise
    },
  })
  const read = reader.read("points", {}, { onData: () => commits++ })
  reader.reset()
  assert.equal(requestSignal.aborted, true)
  pending.resolve(response([{ id: 1 }]))
  await assert.rejects(read, { name: "AbortError" })
  assert.equal(commits, 0)
  reader.destroy()
})

test("reader uses same-origin cookie paths with no account credential", async () => {
  const reader = createReader({
    origin: "https://map.test",
    fetch: async (url, opts) => {
      assert.equal(new URL(url).origin, "https://map.test")
      assert.equal(new URL(url).pathname, "/native/map/data/points")
      assert.equal(opts.credentials, "same-origin")
      assert.equal(opts.headers.Authorization, undefined)
      assert.equal(new URL(url).searchParams.has("api_key"), false)
      return response([])
    },
  })
  assert.deepEqual((await reader.read("points", { import_id: 3 })).data, [])
  await assert.rejects(reader.read("https://external.test/points", {}))
  await assert.rejects(
    reader.read("points", { api_key: "synthetic-forbidden" }),
  )
  reader.destroy()
})

test("exact reader pages are bounded and never silently truncate", async () => {
  const requests = []
  const reader = createReader({
    origin: "https://map.test",
    maxPages: 2,
    maxRows: 3,
    fetch: async (url) => {
      const page = Number(new URL(url).searchParams.get("page"))
      requests.push(page)
      return response([{ id: page }], { "x-total-pages": "2" })
    },
  })
  assert.deepEqual(await reader.pages("points", {}), [{ id: 1 }, { id: 2 }])
  assert.deepEqual(requests, [1, 2])
  await assert.rejects(reader.pages("points", {}, { maxRows: 1 }), /limit/)
  reader.destroy()
})

test("empty data fetch errors and bounds no-data remain distinct", async () => {
  let reply = response([])
  const reader = createReader({
    origin: "https://map.test",
    fetch: async () => reply,
  })
  assert.equal((await reader.read("points", {})).status, "ok")
  reply = response({ point_count: 0 }, {}, 404)
  assert.equal((await reader.read("bounds", {})).status, "no_data")
  reply = response({ error: "unavailable" }, {}, 503)
  await assert.rejects(
    reader.read("points", {}),
    (error) => error.status === 503,
  )
  reader.destroy()
})

test("destroyed readers cancel owned operations without cancelling another owner", async () => {
  const pending = deferred()
  const one = createReader({
    origin: "https://map.test",
    fetch: async () => pending.promise,
  })
  const two = createReader({
    origin: "https://map.test",
    fetch: async () => response([{ id: 2 }]),
  })
  const request = one.read("points", {})
  one.destroy()
  pending.resolve(response([{ id: 1 }]))
  await assert.rejects(request, { name: "AbortError" })
  assert.deepEqual((await two.read("points", {})).data, [{ id: 2 }])
  await assert.rejects(one.read("points", {}), { name: "AbortError" })
  two.destroy()
})

test("reader deadlines abort their own request and clear the matching timer", async () => {
  const pending = deferred()
  let deadline
  let cleared = 0
  let signal
  const reader = createReader({
    origin: "https://map.test",
    timers: {
      setTimeout(callback) {
        deadline = callback
        return 41
      },
      clearTimeout(id) {
        assert.equal(id, 41)
        cleared++
      },
    },
    fetch: async (_, options) => {
      signal = options.signal
      return pending.promise
    },
  })
  const request = reader.read("photos", {})
  assert.equal(typeof deadline, "function")
  deadline()
  assert.equal(signal.aborted, true)
  pending.resolve(response([]))
  await assert.rejects(request, { name: "AbortError" })
  assert.equal(cleared, 1)
  reader.destroy()
})

test("reader deadline settles even when transport ignores abort", async () => {
  const pending = deferred()
  let expire
  const reader = createReader({
    origin: "https://map.test",
    fetch: () => pending.promise,
    timers: {
      setTimeout(fn) {
        expire = fn
        return 1
      },
      clearTimeout() {},
    },
  })
  let settled = false
  const request = reader.read("points").catch((error) => {
    settled = error.name === "AbortError"
  })
  try {
    expire()
    for (let i = 0; i < 12; i++) await Promise.resolve()
    assert.equal(settled, true)
  } finally {
    pending.resolve(response([]))
    await request
    reader.destroy()
  }
})

test("thumbnail reader uses owned cookie bytes and never decodes an image as JSON", async () => {
  const reader = createReader({
    origin: "https://map.test",
    fetch: async (url, opts) => {
      assert.equal(
        new URL(url).pathname,
        "/native/map/data/photos/synthetic-photo/thumbnail",
      )
      assert.equal(opts.headers.Accept, "image/jpeg")
      assert.equal(opts.credentials, "same-origin")
      return new Response(new Uint8Array([255, 216, 255, 217]), {
        headers: { "content-type": "image/jpeg" },
      })
    },
  })
  const result = await reader.read("thumbnail", {
    id: "synthetic-photo",
    source: "immich",
  })
  assert.equal(result.data.type, "image/jpeg")
  assert.deepEqual(
    [...new Uint8Array(await result.data.arrayBuffer())],
    [255, 216, 255, 217],
  )
  reader.destroy()
})
