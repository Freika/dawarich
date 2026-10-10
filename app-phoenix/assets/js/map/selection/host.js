import { createAreaSelection } from "./state.js"
import { createSelectionQuery } from "./query.js"
import { bindTool } from "../ui/host_tools.js"

export function createHostSelection({map, root, reader, pushEvent, lifetime, getConfig}) {
  const panel = root?.querySelector("[data-map-selection]")
  const selection = createAreaSelection({map, query: createSelectionQuery({reader}), getRange: () => getConfig().range, pushEvent,
    onChange: () => {
      if (panel) { panel.hidden = !selection.state.bounds; panel.textContent = String(selection.state.points.length) }
    },
  })
  bindTool(root, '[data-testid="native-select-area"]', selection.start, lifetime)
  const escape = event => { if (event.key === "Escape") selection.cancel() }
  root?.addEventListener("keydown", escape)
  lifetime.own(() => { root?.removeEventListener("keydown", escape); selection.cancel() })
  return selection
}
