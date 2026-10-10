import assert from "node:assert/strict"
import test from "node:test"

async function fixture() {
  const { initializeHttpCredentialQr } = await import(
    "../../app-phoenix/assets/js/http/credential_qr.js"
  )
  const el = new EventTarget()
  const dialog = new EventTarget()
  el.closest = () => dialog
  let resolve
  const ready = new Promise((r) => {
    resolve = r
  })
  const calls = []
  const CredentialQr = {
    mounted() {
      calls.push("mounted")
    },
    reveal() {
      calls.push("reveal")
    },
    clear() {
      calls.push("clear")
    },
    destroyed() {
      calls.push("destroyed")
    },
  }
  const dispose = initializeHttpCredentialQr(el, () => ready)
  const reveal = () => el.dispatchEvent(new Event("dawarich:http-reveal-qr"))
  const flush = async () => {
    await Promise.resolve()
    await Promise.resolve()
  }
  return {
    el,
    dialog,
    resolve: () => resolve({ CredentialQr }),
    calls,
    dispose,
    reveal,
    flush,
  }
}

test("HTTP onboarding reveals through the M4 QR lifecycle and clears on disposal", async () => {
  const f = await fixture()
  f.reveal()
  f.resolve()
  await f.flush()
  assert.deepEqual(f.calls, ["mounted", "reveal"])
  f.dispose()
  assert.deepEqual(f.calls, ["mounted", "reveal", "clear", "destroyed"])
  f.reveal()
  await f.flush()
  assert.equal(f.calls.length, 4)
})

test("HTTP onboarding closing before QR import settles prevents a stale reveal", async () => {
  const f = await fixture()
  f.reveal()
  f.dialog.dispatchEvent(new Event("close"))
  f.resolve()
  await f.flush()
  assert.deepEqual(f.calls, [])
  f.reveal()
  await f.flush()
  assert.deepEqual(f.calls, ["mounted", "reveal"])
})

test("HTTP onboarding disposal before QR import settles prevents initialization", async () => {
  const f = await fixture()
  f.reveal()
  f.dispose()
  f.resolve()
  await f.flush()
  assert.deepEqual(f.calls, [])
})
