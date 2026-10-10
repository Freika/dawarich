import { frameCovers } from "./render/frame_geometry.js"

const METERS_PER_DEGREE = 111320
const SIDECAR_DISTANCE_FACTOR = 1.5
const SIDECAR_DISTANCE_RANGE = [500, 5_000_000]

export function framedDistance(bounds) {
  return (
    (bounds.getNorth() - bounds.getSouth()) *
    METERS_PER_DEGREE *
    SIDECAR_DISTANCE_FACTOR
  )
}

export function sidecarDistance(bounds) {
  const [min, max] = SIDECAR_DISTANCE_RANGE
  return Math.round(Math.min(max, Math.max(min, framedDistance(bounds))))
}

export function saveGuard({ data, center, bounds }, strings = {}) {
  const coords = data?.guardCoords ?? []
  let reason = null
  if (coords.length === 0) reason = strings.no_location_data
  else if (
    !frameCovers(coords, center.lat, center.lng, sidecarDistance(bounds))
  )
    reason = strings.no_tracks_in_frame
  const tooWide = framedDistance(bounds) > SIDECAR_DISTANCE_RANGE[1]
  const message = [
    reason || (tooWide ? strings.frame_too_wide : null),
    data?.flightsOmitted ? strings.gallery_without_flights : null,
  ]
    .filter(Boolean)
    .join(" ")
  return { disabled: Boolean(reason), message }
}

export function saveRecipe({
  state,
  center,
  bounds,
  trackSource,
  strings = {},
}) {
  const title = state.title.trim()
  const range = state.data?.range ?? {}
  return {
    name: title || strings.untitled || "",
    title,
    theme: state.themeKey || "blueprint",
    lat: String(center.lat),
    lon: String(center.lng),
    distance: String(sidecarDistance(bounds)),
    start_at: range.startAt || "",
    end_at: range.endAt || "",
    source: trackSource,
    route_opacity: String(state.opacity),
    route_width: String(state.width),
  }
}

export function bindGalleryControls({
  find,
  on,
  studio,
  poster,
  pushEvent,
  strings = {},
  setStatus,
}) {
  const button = find("save")
  let pending = false

  function refresh() {
    const map = studio.map
    if (!button || !map) return
    const guard = saveGuard(
      {
        data: studio.state.data,
        center: map.getCenter(),
        bounds: map.getBounds(),
      },
      strings,
    )
    button.disabled = guard.disabled || pending
    const notice = find("save-notice")
    if (!notice) return
    notice.textContent = guard.message
    notice.classList.toggle("hidden", !guard.message)
  }

  on(button, "click", () => {
    const map = studio.map
    if (!map || pending || button.disabled) return
    pending = true
    button.disabled = true
    const recipe = saveRecipe({
      state: studio.state,
      center: map.getCenter(),
      bounds: map.getBounds(),
      trackSource: poster.trackSource,
      strings,
    })
    setStatus(strings.queued ?? "")
    Promise.resolve(pushEvent("poster:save", recipe))
      .then(
        (reply) => {
          if (reply?.status !== "queued") setStatus("")
        },
        () => setStatus(strings.save_failed ?? ""),
      )
      .finally(() => {
        pending = false
        refresh()
      })
  })

  return { refresh }
}
