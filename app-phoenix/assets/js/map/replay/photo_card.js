import { createRequestScope } from "../data/request_scope.js"
import { photoPopupHTML } from "../ui/photo_popup.js"

export function createReplayPhotoCard({
  photo,
  map,
  library,
  reader,
  document,
  timezone,
  labels,
  URL = globalThis.URL,
}) {
  const scope = createRequestScope()
  const element = document.createElement("button"),
    image = document.createElement("img")
  element.type = "button"
  element.className =
    "absolute h-20 w-20 rounded-lg border-2 border-white shadow-lg overflow-hidden bg-base-100"
  image.className = "h-full w-full object-cover"
  image.alt = photo.filename ?? labels?.["map_info.photo"] ?? ""
  element.setAttribute("aria-label", image.alt)
  element.appendChild(image)
  let popup,
    url,
    destroyed = false
  const feature = {
    type: "Feature",
    geometry: {
      type: "Point",
      coordinates: [Number(photo.lon), Number(photo.lat)],
    },
    properties: photo,
  }
  const close = () => {
    const owned = popup
    popup = null
    owned?.off("close", close)
    owned?.remove()
  }
  const click = (event) => {
    event.stopPropagation()
    if (destroyed) return
    close()
    popup = new library.Popup({
      closeButton: true,
      closeOnClick: true,
      maxWidth: "400px",
    })
      .setLngLat(feature.geometry.coordinates)
      .setHTML(photoPopupHTML(feature, { url, timezone, labels }))
      .addTo(map)
      .on("close", close)
  }
  element.addEventListener("click", click)
  const ready = (async () => {
    const operation = scope.begin()
    try {
      const { data } = await operation.wait(
        reader.read(
          "thumbnail",
          { id: photo.id, source: photo.source },
          { signal: operation.signal },
        ),
      )
      operation.check()
      url = URL.createObjectURL(data)
      image.src = url
      popup?.setHTML(photoPopupHTML(feature, { url, timezone, labels }))
    } catch {
    } finally {
      operation.close()
    }
  })()
  return {
    element,
    ready,
    remove() {
      if (destroyed) return
      destroyed = true
      scope.destroy()
      close()
      element.removeEventListener("click", click)
      if (url) URL.revokeObjectURL(url)
      url = null
      image.removeAttribute?.("src")
      element.remove()
    },
  }
}
