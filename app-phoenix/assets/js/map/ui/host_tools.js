import { mapNotify } from "./notify.js"
import { createAreaEditor } from "./area_editor.js"
import { createEntityEditor } from "./entity_editor.js"
import { installHostShortcuts } from "./shortcuts.js"
import { createInfoCard } from "./info_card.js"
import { createPointSelection } from "./point_selection.js"

export function bindTool(root, selector, callback, lifetime) {
  if (!root) return
  const click = (event) => {
    const button = event.target?.closest?.(selector)
    if (
      button &&
      root.contains(button) &&
      button.closest("[data-native-map-root]") === root
    )
      callback(event)
  }
  root.addEventListener("click", click)
  lifetime.own(() => root.removeEventListener("click", click))
}

export function createHostTools({ map, root, pushEvent, lifetime, getConfig }) {
  installHostShortcuts({ root, lifetime })
  const notify = mapNotify(getConfig)
  const clear = () => {
    if (root?.dataset) delete root.dataset.mapToolArmed
  }
  const send = (...args) => {
    clear()
    pushEvent(...args)
  }
  const entity = createEntityEditor({ map, pushEvent: send })
  const arm = (kind) => {
    area.disarm()
    entity.arm(kind)
    if (root?.dataset) root.dataset.mapToolArmed = kind
    notify("info", kind === "visit" ? "messages.click_on_the_map_to_place_a_visit_esc_to" : "messages.click_on_the_map_to_place_a_place")
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
  const info = createInfoCard({ root, pushEvent, getConfig, lifetime })
  createPointSelection({ map, lifetime, getConfig, info })
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
      if (root?.dataset) root.dataset.mapToolArmed = "area"
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
  return { area, entity, info }
}
