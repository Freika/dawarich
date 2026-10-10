import { createAreaEditor } from "./area_editor.js"

export function bindTool(root, selector, callback, lifetime) {
  const button = root?.querySelector(selector)
  if (!button) return
  button.addEventListener("click", callback)
  lifetime.own(() => button.removeEventListener("click", callback))
}

export function createHostTools({ map, root, pushEvent, lifetime }) {
  const area = createAreaEditor({ map, pushEvent })
  lifetime.own(area.destroy)
  bindTool(root, '[data-testid="native-create-area"]', area.arm, lifetime)
  return { area }
}
