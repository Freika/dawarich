import assert from "node:assert/strict"
import test from "node:test"
import { launchRequestedStudio } from "../../priv/static/js/hooks/requested_studio.js"

function fixture(query = "?studio=video") {
  let ready = false, opens = 0, disconnected = 0, observe
  const provider = { get controller() { return ready ? { map: {}, mapDataManager: {} } : null } }
  const studio = { open(value) { assert.equal(value, provider); opens++ } }
  class Observer {
    constructor(callback) { observe = callback }
    observe() {}
    disconnect() { disconnected++ }
  }
  const stop = launchRequestedStudio(studio, provider, { query, Observer, root: {} })
  return { stop, ready() { ready = true; observe?.() }, opens: () => opens, disconnected: () => disconnected }
}

test("requested video waits for the real map provider and opens once", () => {
  const f = fixture()
  assert.equal(f.opens(), 0)
  f.ready()
  assert.equal(f.opens(), 1)
  f.ready()
  assert.equal(f.opens(), 1)
  assert.equal(f.disconnected(), 1)
})

test("destroying a requested studio cancels its pending map launch", () => {
  const f = fixture()
  f.stop()
  f.ready()
  assert.equal(f.opens(), 0)
})

test("an ordinary map visit does not launch a video studio", () => {
  const f = fixture("?studio=poster")
  f.ready()
  assert.equal(f.opens(), 0)
})
