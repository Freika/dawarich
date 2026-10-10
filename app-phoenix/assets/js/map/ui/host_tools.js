import { createAreaEditor } from "./area_editor.js"
import { createEntityEditor } from "./entity_editor.js"

export function bindTool(root, selector, callback, lifetime) {
  const button = root?.querySelector(selector)
  if (!button) return
  button.addEventListener("click", callback)
  lifetime.own(() => button.removeEventListener("click", callback))
}

export function createHostTools({ map, root, pushEvent, lifetime }) {
  const entity = createEntityEditor({ map, pushEvent })
  lifetime.own(entity.destroy)
  bindTool(
    root,
    '[data-testid="native-create-place"]',
    () => entity.arm("place"),
    lifetime,
  )
  bindTool(
    root,
    '[data-testid="native-create-visit"]',
    () => entity.arm("visit"),
    lifetime,
  )
  const address = (event) => {
    const point = event.features?.[0]?.properties
    if (
      point &&
      !point.cluster &&
      Number(point.count ?? 1) <= 1 &&
      Number(point.point_count ?? 1) <= 1
    )
      entity.address(point)
  }
  map.on("click", "points-mvt", address)
  lifetime.own(() => map.off("click", "points-mvt", address))
  const area = createAreaEditor({ map, pushEvent })
  lifetime.own(area.destroy)
  bindTool(root, '[data-testid="native-create-area"]', area.arm, lifetime)
  return { area, entity }
}
