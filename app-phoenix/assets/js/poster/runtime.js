import { createPosterSource } from "./source.js"

export function mountPosterStudio({ root, source, fallbackBounds }) {
  const poster = createPosterSource(source, { fallbackBounds })
  return {
    poster,
    async open() {
      root.dataset.posterState = "loading"
      try {
        const data = await poster.load()
        root.dataset.posterState = data.guardCoords.length ? "ready" : "empty"
      } catch (error) {
        if (error?.name !== "AbortError") root.dataset.posterState = "failed"
      }
    },
    destroy() {
      poster.destroy()
      delete root.dataset.posterState
    },
  }
}
