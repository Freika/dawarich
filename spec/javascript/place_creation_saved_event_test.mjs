import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/place_creation_controller.js",
    import.meta.url,
  ),
  "utf8",
)
const { default: PlaceCreationController } = await import(
  `data:text/javascript;base64,${Buffer.from(
    `class Controller {}
     const translate = (key) => key
     ${source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")}`,
  ).toString("base64")}`
)

function setup() {
  const listeners = {}
  const dispatched = []
  const dataEl = { dataset: {} }
  globalThis.CustomEvent = class {
    constructor(type, init) {
      this.type = type
      this.detail = init?.detail
    }
  }
  globalThis.document = {
    addEventListener: (type, fn) => {
      listeners[type] = fn
    },
    removeEventListener: (type) => delete listeners[type],
    getElementById: (id) => (id === "place-creation-data" ? dataEl : null),
    dispatchEvent: (event) => dispatched.push(event),
  }
  const controller = new PlaceCreationController()
  controller.close = () => {}
  controller.connect()
  const streamRender = (target, place) => {
    const event = {
      target: { target },
      detail: {
        render: async () => {
          if (place) {
            dataEl.dataset.place = JSON.stringify(place)
            dataEl.dataset.updated = "true"
          }
        },
      },
    }
    listeners["turbo:before-stream-render"](event)
    return event.detail.render({})
  }
  return { controller, dispatched, streamRender }
}

test("the saved place is announced once its data has been rendered", async () => {
  const { controller, dispatched, streamRender } = setup()

  controller.onSubmitEnd({ detail: { success: true } })
  assert.equal(dispatched.length, 0)

  await streamRender("place-creation-data", { id: 3, name: "Home" })

  assert.deepEqual(
    dispatched.map((e) => [e.type, e.detail.place.id]),
    [["place:updated", 3]],
  )
})

test("each save announces its own place, never the previous one", async () => {
  const { controller, dispatched, streamRender } = setup()

  controller.onSubmitEnd({ detail: { success: true } })
  await streamRender("place-creation-data", { id: 3 })
  controller.onSubmitEnd({ detail: { success: true } })
  await streamRender("place-creation-data", { id: 4 })

  assert.deepEqual(
    dispatched.map((e) => e.detail.place.id),
    [3, 4],
  )
})

test("other streams announce nothing", async () => {
  const { dispatched, streamRender } = setup()

  await streamRender("flash-messages")

  assert.equal(dispatched.length, 0)
})
