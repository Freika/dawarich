import assert from "node:assert/strict"
import { test } from "node:test"

const load = () => import("../../app-phoenix/assets/js/http/auth_forms.js")
class Element extends EventTarget {
  attrs = new Map()
  disabled = false
  setAttribute(k, v) { this.attrs.set(k, String(v)) }
  removeAttribute(k) { this.attrs.delete(k) }
  getAttribute(k) { return this.attrs.get(k) ?? null }
}
function fixture() {
  const password = new Element(), submitter = new Element(), form = new Element()
  submitter.name = "commit"; submitter.value = "Log in"
  form.controls = [password, submitter]
  form.elements = form.controls
  form.valid = true
  form.checkValidity = () => form.valid
  form.querySelectorAll = () => [submitter]
  const summary = { focused: false, focus() { this.focused = true } }
  const doc = { querySelectorAll: () => [form], querySelector: selector => selector === "[data-auth-error-summary]" ? summary : password }
  const win = new EventTarget()
  const submit = (button = submitter) => {
    const event = new Event("submit", { cancelable: true })
    Object.defineProperty(event, "submitter", { value: button })
    form.dispatchEvent(event)
    return event
  }
  return { password, submitter, form, summary, doc, win, submit }
}

test("HTTP submit accepts Enter or click once without dropping commit or credentials", async () => {
  const { initializeAuthForms } = await load()
  for (const enter of [false, true]) {
    const f = fixture(); initializeAuthForms(f.doc, f.win)
    const first = f.submit(enter ? null : f.submitter)
    assert.equal(first.defaultPrevented, false)
    assert.equal(f.form.getAttribute("aria-busy"), "true")
    assert.equal(f.password.disabled, false)
    assert.equal(f.submitter.disabled, false)
    assert.equal(f.submitter.name, "commit")
    assert.equal(f.submitter.value, "Log in")
    assert.equal(f.submit().defaultPrevented, true)
  }
})
test("invalid form remains retryable", async () => {
  const { initializeAuthForms } = await load(); const f = fixture()
  initializeAuthForms(f.doc, f.win); f.form.valid = false
  f.submit(); assert.equal(f.form.getAttribute("aria-busy"), null)
  f.form.valid = true; assert.equal(f.submit().defaultPrevented, false)
})
test("pageshow restores a submitted form", async () => {
  const { initializeAuthForms } = await load(); const f = fixture()
  const dispose = initializeAuthForms(f.doc, f.win)
  f.submit(); f.win.dispatchEvent(new Event("pageshow"))
  assert.equal(f.form.getAttribute("aria-busy"), null)
  assert.equal(f.submitter.getAttribute("aria-disabled"), null)
  assert.equal(f.submit().defaultPrevented, false)
  dispose(); assert.equal(f.submit().defaultPrevented, false)
})
test("error summary receives focus without reading credential values", async () => {
  const { initializeAuthForms } = await load(); const f = fixture()
  Object.defineProperty(f.password, "value", { get() { throw new Error("credential read") } })
  initializeAuthForms(f.doc, f.win); assert.equal(f.summary.focused, true)
})
