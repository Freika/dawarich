import { bindTool } from "../ui/host_tools.js"
import { mapTranslate } from "../ui/translate.js"
import { createSelectionActions } from "./actions.js"
import { createSelectionDrawing } from "./drawing.js"
import { createSelectionQuery } from "./query.js"
import { createAreaSelection } from "./state.js"

const CANCEL_ICON =
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="w-5 h-5"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>'

export function createHostSelection({
  map,
  root,
  reader,
  pushEvent,
  lifetime,
  getConfig,
}) {
  const panel = root?.querySelector("[data-map-selection]")
  const drawing = createSelectionDrawing(map)
  const button = root?.querySelector('[data-testid="native-select-area"]')
  const status = root?.querySelector("[data-map-tool-status]")
  const idle = [...(button?.childNodes ?? [])]
  let actions
  const selection = createAreaSelection({
    map,
    query: createSelectionQuery({ reader }),
    getRange: () => getConfig().range,
    pushEvent,
    onDraw: drawing.draw,
    onChange: () => {
      if (selection.state.active) {
        drawing.draw(selection.state.bounds)
        drawing.highlight(selection.state.points)
      } else drawing.clear()
      if (button) {
        if (selection.state.active) {
          const doc = button.ownerDocument ?? globalThis.document
          button.innerHTML = CANCEL_ICON
          if (doc)
            button.append(
              doc.createTextNode(` ${button.dataset.mapCancelMessage} `),
            )
        } else button.replaceChildren(...idle)
        button.setAttribute("aria-pressed", String(selection.state.active))
      }
      if (status)
        status.textContent =
          selection.state.active && !selection.state.bounds
            ? (button?.dataset.mapDrawMessage ?? "")
            : ""
      if (panel) {
        panel.classList.toggle("hidden", !selection.state.bounds)
        actions?.render()
      }
    },
  })
  if (panel)
    actions = createSelectionActions({
      container: panel,
      document: root.ownerDocument ?? globalThis.document,
      translate: mapTranslate(getConfig),
      selection,
    })
  bindTool(
    root,
    '[data-testid="native-select-area"]',
    () => {
      if (selection.state.active) selection.cancel()
      else {
        selection.start()
        map.getCanvas().focus?.()
      }
    },
    lifetime,
  )
  const onEscape = (event) => {
    if (event.key === "Escape") selection.cancel()
  }
  root?.addEventListener("keydown", onEscape)
  lifetime.own(() => {
    root?.removeEventListener("keydown", onEscape)
    selection.cancel()
    actions?.destroy()
    drawing.clear()
  })
  return selection
}
