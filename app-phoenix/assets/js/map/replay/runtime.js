import { ReplayManager } from "./manager.js"

const SOURCE = "native-replay-marker"
const LAYER = SOURCE
const MINUTES_PER_SECOND = 10

export function createReplay({
  map,
  loadDay,
  timezone,
  raf = globalThis.requestAnimationFrame,
  cancelRaf = globalThis.cancelAnimationFrame,
  onPoint = () => {},
  onState = () => {},
}) {
  const manager = new ReplayManager({ timezone })
  let generation = 0
  let controller = null
  let frame = null
  let playing = false
  let opened = false
  let minute = 0
  let last = null

  const onMarkerClick = () =>
    manager.pinPoint(manager.getPointAtPosition(minute))

  function marker(point) {
    const coordinates = manager.getCoordinates(point)
    if (!coordinates) return
    const data = {
      type: "Feature",
      geometry: {
        type: "Point",
        coordinates: [coordinates.lon, coordinates.lat],
      },
      properties: {},
    }
    const source = map.getSource(SOURCE)
    if (source) return source.setData(data)
    map.addSource(SOURCE, { type: "geojson", data })
    map.addLayer({
      id: LAYER,
      type: "circle",
      source: SOURCE,
      paint: { "circle-radius": 8, "circle-color": "#2563eb" },
    })
    map.on("click", LAYER, onMarkerClick)
  }

  function removeMarker() {
    if (map.getLayer(LAYER)) {
      map.off("click", LAYER, onMarkerClick)
      map.removeLayer(LAYER)
    }
    if (map.getSource(SOURCE)) map.removeSource(SOURCE)
  }

  async function open(range) {
    stop()
    controller?.abort()
    const current = ++generation
    controller = new AbortController()
    opened = true
    const points = await loadDay(range, { signal: controller.signal })
    if (current !== generation || !opened) return "stale"
    manager.setPoints(points)
    minute = manager.findNearestMinuteWithPoints(0) ?? 0
    const point = manager.getPointAtPosition(minute)
    if (point) marker(point)
    onState({ day: manager.getCurrentDay(), minute })
    return "ready"
  }

  function tick(time) {
    frame = null
    if (!playing || !opened) return
    if (last !== null) minute += ((time - last) / 1000) * MINUTES_PER_SECOND
    last = time
    const length = manager.getCurrentDayLengthMinutes()
    if (minute >= length) return stop()
    const point = manager.getPointAtPosition(Math.floor(minute))
    if (point) {
      marker(point)
      onPoint(point)
    }
    frame = raf(tick)
  }

  function play() {
    if (!opened || frame !== null) return
    playing = true
    last = null
    frame = raf(tick)
  }

  function stop() {
    playing = false
    if (frame !== null) cancelRaf(frame)
    frame = null
  }

  function reconnect() {
    if (playing && frame === null) frame = raf(tick)
  }

  function close() {
    generation++
    controller?.abort()
    controller = null
    stop()
    opened = false
    removeMarker()
  }

  return {
    open,
    setDate: open,
    play,
    pause: stop,
    reconnect,
    close,
    manager,
    get playing() {
      return playing
    },
  }
}
