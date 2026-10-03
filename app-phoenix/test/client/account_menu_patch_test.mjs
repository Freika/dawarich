import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

const source = await readFile(new URL("../../priv/static/js/app.js", import.meta.url), "utf8")
let options
const globals = {
  Socket: class {},
  LiveSocket: class {
    constructor(_path, _socket, config) { options = config }
    connect() {}
  },
  MapShell: {}, RailsStimulus: {}, meta: () => null,
  document: { readyState: "loading", addEventListener() {}, querySelectorAll: () => [] },
  window: { addEventListener() {}, setTimeout() {} },
}
vm.runInNewContext(source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, ""), globals)

const client = await readFile(new URL("../../deps/phoenix_live_view/priv/static/phoenix_live_view.esm.js", import.meta.url), "utf8")
const start = client.indexOf("var DOM = {")
const end = client.indexOf("\nvar dom_default = DOM;", start)
assert.ok(start >= 0 && end > start, "installed LiveView DOM implementation required")
const DOM = vm.runInNewContext(`${client.slice(start, end)}\nDOM`)

function element({ open = false, navbar = true, logout = true, title = "old", content = "old action" } = {}) {
  const attrs = new Map([["title", title], ["data-server-revision", title]])
  if (open) attrs.set("open", "")
  return {
    children: [content],
    get attributes() { return [...attrs].map(([name, value]) => ({ name, value })) },
    matches(selector) { return selector === "details" || (selector === ".navbar-end details" && navbar) },
    querySelector(selector) { return selector === 'a[href="/users/sign_out"]' && logout ? {} : null },
    getAttribute(name) { return attrs.get(name) ?? null },
    hasAttribute(name) { return attrs.has(name) },
    setAttribute(name, value) { attrs.set(name, String(value)) },
    removeAttribute(name) { attrs.delete(name) },
    toggleAttribute(name, force) { force ? attrs.set(name, "") : attrs.delete(name) },
  }
}

function reconcile(from, incoming) {
  options.dom?.onBeforeElUpdated?.(from, incoming)
  DOM.mergeAttrs(from, incoming)
}

test("account disclosure survives server reconciliation without rewriting incoming content", () => {
  for (const open of [true, false]) {
    const current = element({ open })
    const incoming = element({ open: !open, title: "server update", content: "updated action" })
    reconcile(current, incoming)
    assert.equal(current.hasAttribute("open"), open)
    assert.equal(current.getAttribute("title"), "server update")
    assert.equal(current.getAttribute("data-server-revision"), "server update")
    assert.deepEqual(incoming.children, ["updated action"])
  }
})

test("unrelated disclosure follows the server instead of keeping account state", () => {
  const current = element({ open: true, navbar: false })
  reconcile(current, element({ navbar: false, title: "server update" }))
  assert.equal(current.hasAttribute("open"), false)
  assert.equal(current.getAttribute("title"), "server update")
})

test("a server removing logout remains free to replace account content and close disclosure", () => {
  const current = element({ open: true })
  const incoming = element({ logout: false, content: "signed-out action", title: "signed out" })
  reconcile(current, incoming)
  assert.equal(current.hasAttribute("open"), false)
  assert.equal(current.getAttribute("title"), "signed out")
  assert.deepEqual(incoming.children, ["signed-out action"])
})
