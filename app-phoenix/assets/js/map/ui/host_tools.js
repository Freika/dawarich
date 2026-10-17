import { createAreaEditor } from "./area_editor.js"
import { createEntityEditor } from "./entity_editor.js"
import { installHostShortcuts } from "./shortcuts.js"
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
  createPointSelection({ map, root, pushEvent, lifetime, getConfig })
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
