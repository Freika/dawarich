import { bindTool } from "../ui/host_tools.js"
import { mapTranslate } from "../ui/translate.js"
import { createSelectionActions } from "./actions.js"
import { createSelectionQuery } from "./query.js"
import { createAreaSelection } from "./state.js"

export function createHostSelection({
  map,
  root,
  reader,
  pushEvent,
  lifetime,
  getConfig,
}) {
  const panel = root?.querySelector("[data-map-selection]")
  let actions
  const selection = createAreaSelection({
    map,
    query: createSelectionQuery({ reader }),
    getRange: () => getConfig().range,
    pushEvent,
    onChange: () => {
      if (panel) {
        panel.hidden = !selection.state.bounds
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
    selection.start,
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
  })
  return selection
}
