import { createRequestScope } from "../data/request_scope.js"
import { createTimelineHover } from "./timeline.js"

export function createHostTimeline({ map, root, reader, lifetime }) {
  const hover = createTimelineHover({ map })
  const requests = createRequestScope()
  let selected
  function clear() {
    selected = null
    requests.reset()
    hover.clear()
  }
  async function enter(event) {
    const id = event.target.closest?.("[data-track-id]")?.dataset.trackId
    if (!id || selected === id) return
    clear()
    selected = id
    const operation = requests.begin()
    try {
      const result = await operation.wait(reader.read("track", { id }, { signal: operation.signal }))
      operation.check()
      hover.hover(result.data)
    } catch {} finally { operation.close() }
  }
  root?.addEventListener("pointerover", enter)
  root?.addEventListener("pointerout", clear)
  lifetime.own(() => {
    root?.removeEventListener("pointerover", enter)
    root?.removeEventListener("pointerout", clear)
    requests.destroy()
    hover.destroy()
  })
  return { config: clear }
}
