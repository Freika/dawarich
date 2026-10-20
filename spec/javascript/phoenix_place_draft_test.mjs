import assert from "node:assert/strict"
import test from "node:test"

const { PlaceDraft } = await import(
  "../../app-phoenix/assets/js/hooks/place_draft.js"
)

function withHook(run) {
  const previous = globalThis.FormData
  globalThis.FormData = class {
    constructor(form) {
      this.values = form.values
    }
    get(key) {
      return this.values[key]
    }
    getAll(key) {
      return this.values[key] || []
    }
  }
  const events = []
  let form = {
    dataset: { placeId: "42" },
    values: {
      "place[name]": "Draft",
      "place[latitude]": "51.12345678",
      "place[longitude]": "12.5",
      "place[note]": "Literal <text>",
      "place[tag_ids][]": ["", "7"],
      "place[source]": "forged",
      api_key: "synthetic-do-not-copy",
    },
  }
  const hook = Object.assign(Object.create(PlaceDraft), {
    el: { dataset: { nativeUserId: "1" }, querySelector: () => form },
    pushEvent: (event, payload) => events.push([event, payload]),
  })
  try {
    run(hook, events, () => {
      form = null
    })
  } finally {
    globalThis.FormData = previous
  }
}

test("Places reconnect recovers only the idle whitelisted draft once without submit", () => {
  withHook((hook, events) => {
    hook.disconnected()
    hook.reconnected()
    hook.reconnected()
    assert.deepEqual(events, [
      [
        "recover_place_draft",
        {
          id: "42",
          place: {
            name: "Draft",
            latitude: "51.12345678",
            longitude: "12.5",
            note: "Literal <text>",
            tag_ids: ["", "7"],
          },
        },
      ],
    ])
  })
})

test("Places reconnect discards a different actor and never recovers absent accepted forms", () => {
  withHook((hook, events, removeForm) => {
    hook.disconnected()
    hook.el.dataset.nativeUserId = "2"
    hook.reconnected()
    hook.el.dataset.nativeUserId = "1"
    hook.reconnected()
    removeForm()
    hook.disconnected()
    hook.reconnected()
    assert.deepEqual(events, [])
  })
})

test("Map reconnect restores the scoped draft once through its recovery event and clears on departure", () => {
  withHook((hook, events) => {
    hook.el.dataset.nativeDraftEvent = "place:recover"
    hook.disconnected()
    hook.reconnected()
    hook.reconnected()
    assert.equal(events.length, 1)
    assert.equal(events[0][0], "place:recover")
    assert.equal(events[0][1].place.name, "Draft")
    assert.equal(events[0][1].place.source, undefined)
    hook.disconnected()
    hook.destroyed()
    hook.reconnected()
    assert.equal(events.length, 1)
  })
})
