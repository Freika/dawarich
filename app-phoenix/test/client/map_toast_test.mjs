import assert from "node:assert/strict"
import test from "node:test"
import { toastDocument } from "./support/toast_dom.mjs"
import { Toast } from "../../assets/js/map/ui/toast.js"


test("Rails toast markup colors safe text and exact slide styles", t => {
  t.mock.timers.enable({ apis: ["setTimeout"] })
  globalThis.document = toastDocument()
  Toast.container = null
  const toast = Toast.info("<b>New location recorded</b>")
  assert.equal(Toast.container.className, "toast-container")
  assert.match(Toast.container.style.cssText, /top: 20px;/)
  assert.match(Toast.container.style.cssText, /right: 20px;/)
  assert.match(Toast.container.style.cssText, /pointer-events: none;/)
  assert.equal(toast.className, "toast toast-info")
  assert.equal(toast.children[0].textContent, "<b>New location recorded</b>")
  assert.match(toast.style.cssText, /background: #3b82f6;/)
  assert.match(document.head.textContent, /animation: toast-slide-out 0.3s ease-out;/)
  Toast.success("ok")
  assert.equal(document.head.children.length, 1)
})

test("Rails toast durations and dismiss animation expire at exact boundaries", t => {
  t.mock.timers.enable({ apis: ["setTimeout"] })
  globalThis.document = toastDocument()
  Toast.container = null
  const nodes = [Toast.info("i"), Toast.success("s"), Toast.warning("w"), Toast.error("e")]
  t.mock.timers.tick(2999)
  assert.equal(nodes[0].classList.contains("removing"), false)
  t.mock.timers.tick(1)
  assert.equal(nodes[0].classList.contains("removing"), true)
  assert.equal(nodes[1].classList.contains("removing"), true)
  t.mock.timers.tick(300)
  assert.equal(Toast.container.children.length, 2)
  t.mock.timers.tick(200)
  assert.equal(nodes[2].classList.contains("removing"), true)
  t.mock.timers.tick(500)
  assert.equal(nodes[3].classList.contains("removing"), true)
  t.mock.timers.tick(300)
  assert.equal(Toast.container.children.length, 0)
})

test("Rails retry stays until its action dismisses and clearAll dismisses persistent countdown", t => {
  t.mock.timers.enable({ apis: ["setTimeout"] })
  globalThis.document = toastDocument()
  Toast.container = null
  let retries = 0
  const toast = Toast.retry("failed", "Retry", () => retries++)
  const countdown = Toast.info("20 seconds", 0)
  t.mock.timers.tick(20000)
  assert.equal(toast.classList.contains("removing"), false)
  assert.equal(countdown.classList.contains("removing"), false)
  toast.children[1].click()
  assert.equal(retries, 1)
  assert.equal(toast.classList.contains("removing"), true)
  Toast.clearAll()
  assert.equal(countdown.classList.contains("removing"), true)
  t.mock.timers.tick(300)
  assert.equal(Toast.container.children.length, 0)
})
