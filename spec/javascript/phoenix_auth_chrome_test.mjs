import assert from "node:assert/strict"
import { test } from "node:test"
import { initializeAuthForms } from "../../app-phoenix/assets/js/http/auth_forms.js"
import { Dismissible } from "../../app-phoenix/assets/js/hooks/dismissible.js"
const load = () => import("../../app-phoenix/assets/js/http/auth_chrome.js")
class Element extends EventTarget {
  dataset = {}
  removed = false
  attrs = new Map()
  remove() {
    this.removed = true
  }
  setAttribute(k, v) {
    this.attrs.set(k, v)
  }
  removeAttribute(k) {
    this.attrs.delete(k)
  }
  getAttribute(k) {
    return this.attrs.get(k) ?? null
  }
}
function fixture() {
  const success = new Element(),
    alert = new Element(),
    close = new Element(),
    locale = new Element(),
    dismiss = new Element(),
    open = new Element(),
    confirm = new Element()
  success.dataset.authFlashTimeout = "5000"
  alert.dataset.authFlashTimeout = "0"
  close.closest = () => alert
  dismiss.closest = () => locale
  locale.dataset.dismissibleKeyValue = "locale_suggestion_de"
  open.dataset.authOpenDialog = "getting_started"
  confirm.dataset.authConfirm = "Confirm?"
  confirm.checkValidity = () => true
  confirm.querySelectorAll = () => []
  const dialog = {
    opens: 0,
    showModal() {
      this.opens++
    },
  }
  const map = new Map([
    ["[data-auth-flash]", [success, alert]],
    ["[data-auth-flash-dismiss]", [close]],
    ["[data-auth-locale-suggestion]", [locale]],
    ["[data-auth-locale-dismiss]", [dismiss]],
    ["[data-auth-open-dialog]", [open]],
    ["form[data-auth-confirm]", [confirm]],
    ["form[data-auth-form]", [confirm]],
  ])
  const doc = {
    querySelectorAll: (s) => map.get(s) || [],
    querySelector: () => null,
    getElementById: () => dialog,
  }
  const win = new EventTarget(),
    timers = new Map(),
    storage = new Map()
  win.localStorage = {
    getItem: (k) => storage.get(k),
    setItem: (k, v) => storage.set(k, v),
  }
  win.setTimeout = (fn, ms) => {
    const id = timers.size + 1
    timers.set(id, { fn, ms })
    return id
  }
  win.clearTimeout = (id) => timers.delete(id)
  win.confirm = () => false
  return {
    success,
    alert,
    close,
    locale,
    dismiss,
    open,
    confirm,
    dialog,
    doc,
    win,
    timers,
    storage,
  }
}
test("HTTP flash dismisses and success expires without a socket", async () => {
  const { initializeAuthChrome } = await load(),
    f = fixture()
  initializeAuthChrome(f.doc, f.win)
  f.close.dispatchEvent(new Event("click"))
  assert.equal(f.alert.removed, true)
  assert.equal(f.timers.size, 1)
  const timer = [...f.timers.values()][0]
  assert.equal(timer.ms, 5000)
  timer.fn()
  assert.equal(f.success.removed, true)
})
test("HTTP locale dismissal survives reload", async () => {
  const { initializeAuthChrome } = await load(),
    f = fixture()
  initializeAuthChrome(f.doc, f.win)
  f.dismiss.dispatchEvent(new Event("click"))
  assert.equal(f.locale.removed, true)
  const next = fixture()
  next.win.localStorage = f.win.localStorage
  initializeAuthChrome(next.doc, next.win)
  assert.equal(next.locale.removed, true)
})
test("HTTP chrome cleans timers and opens onboarding via keyboard activation", async () => {
  const { initializeAuthChrome } = await load(),
    f = fixture()
  const dispose = initializeAuthChrome(f.doc, f.win)
  f.open.dispatchEvent(new Event("click"))
  assert.equal(f.dialog.opens, 1)
  dispose()
  assert.equal(f.timers.size, 0)
  f.open.dispatchEvent(new Event("click"))
  assert.equal(f.dialog.opens, 1)
})
test("HTTP confirmation cancel remains retryable", async () => {
  const { initializeAuthChrome } = await load(),
    f = fixture()
  initializeAuthChrome(f.doc, f.win)
  initializeAuthForms(f.doc, f.win)
  const canceled = new Event("submit", { cancelable: true })
  Object.defineProperty(canceled, "currentTarget", { value: f.confirm })
  f.confirm.dispatchEvent(canceled)
  assert.equal(canceled.defaultPrevented, true)
  assert.equal(f.confirm.getAttribute("aria-busy"), null)
  f.win.confirm = () => true
  const accepted = new Event("submit", { cancelable: true })
  Object.defineProperty(accepted, "currentTarget", { value: f.confirm })
  f.confirm.dispatchEvent(accepted)
  assert.equal(accepted.defaultPrevented, false)
  assert.equal(f.confirm.getAttribute("aria-busy"), "true")
})

test("native locale dismissal remains dismissed on HTTP documents", async () => {
  const { initializeAuthChrome } = await load()
  const f = fixture()
  globalThis.localStorage = f.win.localStorage
  const hook = { ...Dismissible, el: f.locale }
  hook.mounted()
  const click = new Event("click")
  Object.defineProperty(click, "target", { value: { closest: () => ({}) } })
  f.locale.dispatchEvent(click)
  hook.destroyed()
  const next = fixture()
  next.win.localStorage = f.win.localStorage
  initializeAuthChrome(next.doc, next.win)
  assert.equal(next.locale.removed, true)
  delete globalThis.localStorage
})

test("HTTP locale dismissal remains dismissed in the native hook", async () => {
  const { initializeAuthChrome } = await load()
  const f = fixture()
  const dispose = initializeAuthChrome(f.doc, f.win)
  f.dismiss.dispatchEvent(new Event("click"))
  const next = fixture()
  globalThis.localStorage = f.win.localStorage
  const hook = { ...Dismissible, el: next.locale }
  hook.mounted()
  assert.equal(next.locale.hidden, true)
  hook.destroyed()
  dispose()
  delete globalThis.localStorage
})

test("HTTP locale dismissal accepts only the native stored value one", async () => {
  const { initializeAuthChrome } = await load()
  for (const value of ["0", "false", "", "1"]) {
    const f = fixture()
    f.storage.set("dismissed:locale_suggestion_de", value)
    f.storage.set("locale_suggestion_de", value)
    initializeAuthChrome(f.doc, f.win)
    assert.equal(f.locale.removed, value === "1")
  }
})
