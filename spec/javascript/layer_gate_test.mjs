import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/layer_gate.js",
    import.meta.url,
  ),
  "utf8",
)
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const moduleSource = `
  const translate = (key) => key
  const Toast = { info: () => ({}), dismiss() {} }
  const UpgradeBanner = { show() {} }
  ${withoutImports}
`
const { gatedToggle } = await import(
  `data:text/javascript;base64,${Buffer.from(moduleSource).toString("base64")}`
)

function toggleWith({ layer, checked }) {
  const hidden = []
  const intercepted = gatedToggle({
    layer,
    layerName: layer,
    gatedLayers: ["Heatmap", "Hexagons"],
    userPlan: "lite",
    toggle: { checked },
    showFn: async () => {},
    hideFn: () => hidden.push(layer),
    upgradeUrl: "/upgrade",
  })
  return { intercepted, hidden }
}

test("a Lite toggle is left alone when the server does not gate that layer", () => {
  assert.equal(
    toggleWith({ layer: "Fog of War", checked: false }).intercepted,
    false,
  )
})

test("a Lite toggle of a server-gated layer is intercepted", () => {
  const { intercepted, hidden } = toggleWith({
    layer: "Hexagons",
    checked: false,
  })
  assert.equal(intercepted, true)
  assert.deepEqual(hidden, ["Hexagons"])
})
