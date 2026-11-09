import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre/event_handlers.js",
    import.meta.url,
  ),
  "utf8",
)
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const stubs = `const translate = (key) => key
class TrackSelection {}
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
