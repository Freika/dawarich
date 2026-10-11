import { createAreaEditor } from "./area_editor.js"
import { createEntityEditor } from "./entity_editor.js"

export function bindTool(root, selector, callback, lifetime) {
  const button = root?.querySelector(selector)
  if (!button) return
  button.addEventListener("click", callback)
  lifetime.own(() => button.removeEventListener("click", callback))
}

export function createHostTools({ map, root, pushEvent, lifetime }) {
  const status = root?.querySelector("[data-map-tool-status]")
  const clear = () => {
    if (status) status.textContent = ""
  }
  const send = (...args) => {
    clear()
    pushEvent(...args)
  }
  const entity = createEntityEditor({ map, pushEvent: send })
  const arm = (kind) => {
    area.disarm()
    entity.arm(kind)
    if (status) status.textContent = status.dataset[`${kind}Message`] ?? ""
    map.getCanvas().focus?.()
  }
  lifetime.own(clear)
  lifetime.own(entity.destroy)
  bindTool(
    root,
    '[data-testid="native-create-place"]',
    () => arm("place"),
    lifetime,
  )
  bindTool(
    root,
    '[data-testid="native-create-visit"]',
    () => arm("visit"),
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
  const area = createAreaEditor({ map, pushEvent: send })
  lifetime.own(area.destroy)
  const preview = ({ detail }) => (detail ? area.preview(detail) : area.clear())
  root?.addEventListener("native:area-preview", preview)
  lifetime.own(() => root?.removeEventListener("native:area-preview", preview))
  bindTool(
    root,
    '[data-testid="native-create-area"]',
    () => {
      entity.disarm()
      clear()
      area.arm()
      map.getCanvas().focus?.()
    },
    lifetime,
  )
  const cancel = (event) => {
    if (event.key !== "Escape") return
    entity.disarm()
    area.disarm()
    clear()
  }
  root?.addEventListener("keydown", cancel)
  lifetime.own(() => root?.removeEventListener("keydown", cancel))
  return { area, entity }
}
