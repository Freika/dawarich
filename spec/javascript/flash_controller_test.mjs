import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/flash_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
)
  .replace(
    'import { Controller } from "@hotwired/stimulus"',
    "class Controller {}",
  )
  .replace('import { translate } from "i18n"', "const translate = (key) => key")
const { default: FlashController } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

function fixture(count = 0) {
  const controller = new FlashController()
  const messages = []
  controller.hasDismissAllTarget = true
  controller.dismissAllTarget = { hidden: true }
  Object.defineProperty(controller, "messageTargets", {
    get: () => messages.filter((message) => !message.removed),
  })
  const addMessage = () => {
    const message = {
      remove() {
        this.removed = true
      },
    }
    messages.push(message)
    controller.messageTargetConnected()
    return message
  }
  for (let i = 0; i < count; i++) addMessage()
  controller.connect()
  return { controller, addMessage }
}

test("bulk dismissal is hidden for zero or one message, and shown for multiple", () => {
  for (const count of [0, 1, 2, 100]) {
    const { controller } = fixture(count)
    assert.equal(controller.dismissAllTarget.hidden, count < 2)
  }
})

test("adding messages and removing them individually updates the control", () => {
  const { controller, addMessage } = fixture(1)
  const second = addMessage()
  assert.equal(controller.dismissAllTarget.hidden, false)
  second.remove()
  controller.messageTargetDisconnected()
  assert.equal(controller.dismissAllTarget.hidden, true)
})

test("one action clears a batch and subsequent messages can still be dismissed", () => {
  const { controller, addMessage } = fixture(100)
  controller.dismissAll()
  controller.messageTargetDisconnected()
  assert.equal(controller.messageTargets.length, 0)
  assert.equal(controller.dismissAllTarget.hidden, true)

  addMessage()
  assert.equal(controller.dismissAllTarget.hidden, true)
  addMessage()
  assert.equal(controller.dismissAllTarget.hidden, false)
  controller.dismissAll()
  assert.equal(controller.messageTargets.length, 0)
})

test("reconnecting refreshes visibility from the remaining messages", () => {
  const { controller } = fixture(2)
  controller.dismissAllTarget.hidden = true
  controller.connect()
  assert.equal(controller.dismissAllTarget.hidden, false)
  controller.messageTargets[0].remove()
  controller.connect()
  assert.equal(controller.dismissAllTarget.hidden, true)
})
