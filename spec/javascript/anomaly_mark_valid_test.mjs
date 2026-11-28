import assert from "node:assert/strict"
import test from "node:test"
import { strippedSource } from "./support/stripped_source.mjs"

const withoutImports = await strippedSource(
  "controllers/maps/maplibre/event_handlers.js",
  { inline: ["controllers/maps/maplibre/track_selection.js"] },
)
const stubs = `const translate = (key) => key
class PointDragGesture {
  attach() {}
  detach() {}
  cancel() {}
  canDrag() { return false }
}
`
const moduleUrl = `data:text/javascript;base64,${Buffer.from(stubs + withoutImports).toString("base64")}`
const { EventHandlers } = await import(moduleUrl)

globalThis.document ??= {
  addEventListener: () => {},
  removeEventListener: () => {},
  dispatchEvent: () => {},
}

test("an anomaly point offers to mark it as correct", () => {
  const shown = []
  const handlers = new EventHandlers(
    {},
    {
      layerManager: {
        getLayer: () => ({ buildPopupContent: () => "<div></div>" }),
      },
      showInfo: (title, content, actions) =>
        shown.push({ title, content, actions }),
    },
  )

  handlers.handleAnomalyClick({ features: [{ properties: { id: 7 } }] })

  assert.deepEqual(shown[0].actions, [
    {
      type: "button",
      handler: "markPointValid",
      id: 7,
      entityType: "point",
      label: "messages.mark_point_valid",
    },
  ])
})
