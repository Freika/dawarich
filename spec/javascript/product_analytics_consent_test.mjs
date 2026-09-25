import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import { runInNewContext } from "node:vm"

const source = await readFile(
  new URL("../../app/javascript/product_analytics_consent.js", import.meta.url),
  "utf8",
)

function visit({
  account = false,
  serverChoice = "unknown",
  browserChoice = null,
  siteChoice = false,
} = {}) {
  const scripts = []
  const requests = []
  const panel = { dataset: {}, hidden: true, querySelectorAll: () => [] }
  const document = {
    readyState: "complete",
    cookie: siteChoice ? "dawarichAttributionConsent=true" : "",
    documentElement: {
      dataset: {
        selfHosted: "false",
        analyticsAccount: String(account),
        analyticsConsent: serverChoice,
        partneroId: "affiliate",
        googleAdsId: "AW-123",
      },
    },
    getElementById: (id) => (id === "product-analytics-choice" ? panel : null),
    querySelector: () => ({ content: "csrf" }),
    querySelectorAll: () => [],
    createElement: () => ({ setAttribute() {} }),
    head: { appendChild: (script) => scripts.push(script.src) },
    addEventListener() {},
  }
  const storage = new Map(
    browserChoice === null
      ? []
      : [["dawarich_product_analytics_consent_v1", browserChoice]],
  )
  const localStorage = { getItem: (key) => storage.get(key) ?? null }
  const window = {}
  runInNewContext(source, {
    document,
    localStorage,
    window,
    fetch: (...args) => {
      requests.push(args)
      return Promise.resolve({ ok: true })
    },
    location: { reload() {} },
    Date,
    JSON,
  })
  return { scripts, requests, panel }
}

test("no optional script or event is sent before consent or after refusal", () => {
  for (const choice of [null, "false"]) {
    const result = visit({ browserChoice: choice })
    assert.deepEqual(result.scripts, [])
    assert.deepEqual(result.requests, [])
  }
})

test("account refusal overrides an older browser acceptance", () => {
  const result = visit({
    account: true,
    serverChoice: "false",
    browserChoice: "true",
    siteChoice: true,
  })
  assert.deepEqual(result.scripts, [])
  assert.deepEqual(result.requests, [])
})

test("product consent alone loads only self-hosted visit analytics", () => {
  const result = visit({ account: true, serverChoice: "true" })
  assert.ok(result.scripts.some((url) => url.includes("rybbit.dwri.xyz")))
  assert.ok(
    result.scripts.every(
      (url) => !/googletagmanager|partnero|simpleanalytics/.test(url),
    ),
  )
  assert.equal(result.requests.length, 1)
})

test("advertising and affiliate scripts require both product and site consent", () => {
  const result = visit({
    account: true,
    serverChoice: "true",
    siteChoice: true,
  })
  assert.ok(result.scripts.some((url) => url.includes("googletagmanager.com")))
  assert.ok(result.scripts.some((url) => url.includes("partnero.com")))
})
