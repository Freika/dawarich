import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/components/toast.js",
    import.meta.url,
  ),
  "utf8",
)
const { Toast } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

// Just enough DOM for Toast: elements that know their parent and children.
function element(tag) {
  return {
    tag,
    children: [],
    parentElement: null,
    className: "",
    style: {},
    classList: { add() {} },
    get isConnected() {
      let node = this
      while (node.parentElement) node = node.parentElement
      return node === globalThis.document.body
    },
    setAttribute() {},
    appendChild(child) {
      child.parentElement = this
      this.children.push(child)
      return child
    },
    prepend(child) {
      child.parentElement = this
      this.children.unshift(child)
    },
    remove() {
      if (!this.parentElement) return
      const siblings = this.parentElement.children
      siblings.splice(siblings.indexOf(this), 1)
      this.parentElement = null
    },
    addEventListener() {},
  }
}

function page({ dock }) {
  const body = element("body")
  const head = element("head")
  const replayDock = dock ? body.appendChild(element("div")) : null
  globalThis.document = {
    body,
    head,
    createElement: element,
    getElementById: () => null,
    querySelector: (selector) =>
      selector === ".map-toast-stack" ? replayDock : null,
  }
  return { body, replayDock }
}

test("on the map a toast sits in the stack under the loading badge", () => {
  const { replayDock } = page({ dock: true })

  Toast.show("No tracks in this view yet", "info", 0)

  assert.equal(replayDock.children[0], Toast.container)
  assert.match(Toast.container.className, /toast-container--docked/)
})

test("after the page changes, toasts go to the new page", () => {
  page({ dock: true })
  Toast.show("first", "info", 0)
  const { body } = page({ dock: false })

  Toast.show("second", "info", 0)

  assert.equal(Toast.container.parentElement, body)
  assert.doesNotMatch(Toast.container.className, /docked/)
})
