import { createRequestScope } from "../data/request_scope.js"
import { photoPopupHTML } from "./photo_popup.js"
export function createPhotoMarker({
  map,
  library,
  reader,
  feature,
  position,
  visible = true,
  document = map.getContainer().ownerDocument,
  URL = globalThis.URL,
  timers = globalThis,
  labels,
  timezone,
  onError,
}) {
  const operations = createRequestScope(timers),
    controller = new AbortController()
  const container = document.createElement("div"),
    element = document.createElement("div")
  container.style.display = visible ? "block" : "none"
  element.className = "photo-marker"
  element.style.cssText =
    "width:50px;height:50px;border-radius:50%;cursor:pointer;background-size:cover;background-position:center;border:3px solid white;box-shadow:0 2px 4px rgba(0,0,0,0.3);transition:transform 0.2s,box-shadow 0.2s;"
  container.appendChild(element)
  const marker = new library.Marker({ element: container })
    .setLngLat(position ?? feature.geometry.coordinates)
    .addTo(map)
  let popup,
    url,
    removed = false
  const close = () => {
    const owned = popup
    popup = null
    owned?.off("close", close)
    owned?.remove()
  }
  const html = () =>
    photoPopupHTML(feature, {
      url,
      timezone,
      labels,
      theme:
        document.documentElement
          ?.getAttribute("data-theme")
          ?.includes("dark") ||
        document.documentElement?.classList.contains("dark")
          ? "dark"
          : "light",
    })
  const enter = () => {
    element.style.transform = "scale(1.2)"
    element.style.boxShadow = "0 4px 8px rgba(0,0,0,0.4)"
    element.style.zIndex = "1000"
  }
  const leave = () => {
    element.style.transform = "scale(1)"
    element.style.boxShadow = "0 2px 4px rgba(0,0,0,0.3)"
    element.style.zIndex = "1"
  }
  const click = (event) => {
    event.stopPropagation()
    if (removed) return
    close()
    popup = new library.Popup({
      closeButton: true,
      closeOnClick: true,
      maxWidth: "400px",
    })
      .setLngLat(feature.geometry.coordinates)
      .setHTML(html())
      .addTo(map)
      .on("close", close)
  }
  for (const [event, handler] of [
    ["mouseenter", enter],
    ["mouseleave", leave],
    ["click", click],
  ])
    element.addEventListener(event, handler)
  const disposeMarker = marker.remove.bind(marker)
  marker.remove = () => {
    if (removed) return
    removed = true
    controller.abort()
    operations.destroy()
    close()
    for (const [event, handler] of [
      ["mouseenter", enter],
      ["mouseleave", leave],
      ["click", click],
    ])
      element.removeEventListener(event, handler)
    if (url) URL.revokeObjectURL(url)
    url = null
    disposeMarker()
  }
  marker.ready = (async () => {
    const operation = operations.begin(controller.signal)
    try {
      const response = await operation.wait(
        reader.read(
          "thumbnail",
          { id: feature.properties.id, source: feature.properties.source },
          { signal: operation.signal },
        ),
      )
      operation.check()
      url = URL.createObjectURL(response.data)
      element.style.backgroundImage = `url("${url}")`
      popup?.setHTML(html())
    } catch {
      if (!removed && !controller.signal.aborted)
        onError?.("photo_thumbnail_failed")
    } finally {
      operation.close()
    }
  })()
  return marker
}
