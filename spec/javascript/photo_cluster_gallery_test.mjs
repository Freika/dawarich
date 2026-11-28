import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

// Small DOM double: browser coverage uses the real dialog and MapLibre worker.
class Element {
  constructor(tag) {
    this.tag = tag
    this.children = []
    this.attributes = {}
    this.listeners = {}
    this.isConnected = true
  }
  append(...children) {
    this.children.push(...children)
  }
  replaceChildren(...children) {
    this.children = children
  }
  setAttribute(key, value) {
    this.attributes[key] = value
  }
  removeAttribute(key) {
    delete this.attributes[key]
  }
  addEventListener(key, fn) {
    this.listeners[key] = fn
  }
  remove() {
    this.isConnected = false
  }
  focus() {
    this.focused = true
  }
  showModal() {
    this.open = true
  }
  close() {
    this.open = false
    this.listeners.close?.()
  }
}
globalThis.document = {
  createElement: (tag) => new Element(tag),
  body: new Element("body"),
  createTextNode: (text) => ({ text }),
}
const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/components/photo_cluster_gallery.js",
    import.meta.url,
  ),
  "utf8",
)
const { PhotoClusterGallery, PHOTO_CLUSTER_PAGE_SIZE } = await import(
  `data:text/javascript;base64,${Buffer.from(`${source.replace(/^import .*\n/gm, "")}\nconst translate=(key,values={})=>key+JSON.stringify(values); const PhotoPopupFactory={};`).toString("base64")}`
)
const leaf = (i) => ({
  properties: {
    id: i,
    filename: "<script>photo</script>",
    thumbnail_url: "/thumbnail?api_key=synthetic&source=immich",
  },
})
const tick = () => new Promise((resolve) => setImmediate(resolve))
function gallery(loadPage, total = 1001) {
  return new PhotoClusterGallery({
    loadPage,
    total,
    returnFocus: new Element("canvas"),
  }).open()
}

test("loads only 24 leaves at the requested offset and replaces the previous page", async () => {
  const calls = []
  const g = gallery(async (limit, offset) => {
    calls.push([limit, offset])
    return Array.from({ length: limit }, (_, i) => leaf(offset + i))
  })
  await tick()
  assert.deepEqual(calls, [[24, 0]])
  assert.equal(g.content.children[0].children.length, 24)
  assert.equal(
    g.content.children[0].children[0].children[0].src,
    "/thumbnail?api_key=synthetic&source=immich",
  )
  assert.equal(
    g.content.children[0].children[0].attributes["aria-label"],
    "<script>photo</script>",
  )
  assert.equal(g.previous.disabled, true)
  await g.showPage(PHOTO_CLUSTER_PAGE_SIZE)
  assert.deepEqual(calls, [
    [24, 0],
    [24, 24],
  ])
  assert.equal(g.content.children.length, 1)
  assert.equal(g.previous.disabled, false)
  g.close()
})

test("last page disables Next; empty page is recoverable using Previous", async () => {
  const g = gallery(async () => [leaf(0)], 25)
  await g.showPage(24)
  assert.equal(g.next.disabled, true)
  g.loadPage = async () => []
  await g.showPage(24)
  assert.match(g.status.textContent, /empty/)
  assert.equal(g.next.disabled, true)
  assert.equal(g.previous.disabled, false)
  g.close()
})

test("rejected requests expose Retry; a subsequent attempt renders photos", async () => {
  const g = gallery(async () => {
    throw new Error("synthetic")
  })
  await tick()
  assert.match(g.status.textContent, /error/)
  assert.equal(g.content.children[0].textContent, "photo_cluster.retry{}")
  g.loadPage = async () => [leaf(0)]
  await g.showPage(0)
  assert.match(g.status.textContent, /range/)
  g.close()
})

test("late pages cannot replace a newer page", async () => {
  let finish
  const g = gallery(
    () =>
      new Promise((resolve) => {
        finish = resolve
      }),
  )
  g.loadPage = async () => [leaf(24)]
  await g.showPage(24)
  const current = g.content.children[0]
  finish([leaf(0)])
  await tick()
  assert.equal(g.content.children[0], current)
  g.close()
})

test("closing invalidates pending work, removes the dialog and restores focus once", async () => {
  let finish
  const g = gallery(
    () =>
      new Promise((resolve) => {
        finish = resolve
      }),
  )
  let closed = 0
  g.onClose = () => closed++
  g.close()
  finish([leaf(0)])
  await tick()
  assert.equal(g.content.children.length, 0)
  assert.equal(g.dialog.isConnected, false)
  assert.equal(g.returnFocus.focused, true)
  g.destroy()
  assert.equal(closed, 1)
})
