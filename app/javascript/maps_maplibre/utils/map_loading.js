// A spinner on a map's container from the moment the map is asked for until
// its style and first tiles have drawn (the `.map-loading` rule draws it).

/** Show the spinner; call before fetching the map's style. */
export function startMapLoading(container) {
  if (!container?.classList) return
  // The spinner is positioned against the container.
  if (getComputedStyle(container).position === "static") {
    container.style.position = "relative"
  }
  container.classList.add("map-loading")
}

/** Hide the spinner once the map has loaded. */
export function finishMapLoadingOn(map) {
  const container = map.getContainer?.()
  if (!container?.classList) return
  map.once("load", () => container.classList.remove("map-loading"))
}
