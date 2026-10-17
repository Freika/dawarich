import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/onboarding_modal_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import .*\n/gm, "")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(`class Controller {}\n${source}\n//# sourceURL=onboarding_modal_controller.js`).toString("base64")}`
const { default: OnboardingModalController } = await import(moduleUrl)

function controller({ eventUrl = "/settings/onboarding/event" } = {}) {
  const requests = []
  const anonymous = []
  globalThis.fetch = (url, options) => {
    requests.push({ url, options, body: JSON.parse(options.body || "{}") })
    return Promise.resolve({ ok: true })
  }
  globalThis.window = { sa_event: (name) => anonymous.push(name) }
  globalThis.document = {
    querySelector: () => ({ content: "csrf-token" }),
    querySelectorAll: () => [],
  }

  const instance = new OnboardingModalController()
  instance.eventUrlValue = eventUrl
  instance.onboardingUrlValue = "/settings/onboarding"
  instance.closed = false
  instance.modalTarget = {
    close() {
      instance.closed = true
    },
  }
  return { instance, requests, anonymous }
}

const recorded = (requests) =>
  requests
    .filter((r) => r.url === "/settings/onboarding/event")
    .map((r) => r.body.name)

test("records the chosen path on the server", () => {
  const { instance, requests } = controller()

  instance.showImport()
  instance.showTrack()

  assert.deepEqual(recorded(requests), [
    "onboarding_import_selected",
    "onboarding_track_selected",
  ])
  assert.equal(requests[0].options.method, "POST")
  assert.equal(requests[0].options.keepalive, true)
  assert.equal(requests[0].options.headers["X-CSRF-Token"], "csrf-token")
})

test("tells skipping apart from closing after a choice", () => {
  const { instance, requests } = controller()

  instance.skip()

  assert.deepEqual(recorded(requests), ["onboarding_skipped"])
  assert.equal(instance.closed, true)
})

test("records the family path before the link navigates away", () => {
  const { instance, requests } = controller()

  instance.chooseFamily()

  assert.deepEqual(recorded(requests), ["onboarding_family_selected"])
  assert.equal(requests[0].options.keepalive, true)
  assert.equal(instance.closed, true)
})

test("persists completion with keepalive and keeps it out of the step log", () => {
  const { instance, requests, anonymous } = controller()

  instance.completeOnboarding()

  assert.deepEqual(recorded(requests), [])
  const completion = requests.find((r) => r.url === "/settings/onboarding")
  assert.equal(completion.options.method, "PATCH")
  assert.equal(completion.options.keepalive, true)
  assert.deepEqual(anonymous, ["onboarding_completed"])
})

test("sends nothing to the server without an event URL", () => {
  const { instance, requests, anonymous } = controller({ eventUrl: "" })

  instance.showImport()

  assert.deepEqual(recorded(requests), [])
  assert.deepEqual(anonymous, ["onboarding_import_selected"])
})
