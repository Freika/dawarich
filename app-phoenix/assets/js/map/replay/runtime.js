import { createFollowCamera } from "./follow.js"
import { ReplayManager } from "./manager.js"
import { createStepper } from "./playback.js"

const SOURCE = "native-replay-marker"
const LAYER = SOURCE
const PULSE = `${LAYER}-pulse`
const ORANGE = "#f97316"

export function createReplay({
  map,
  loadDay,
  timezone,
  raf = globalThis.requestAnimationFrame,
  cancelRaf = globalThis.cancelAnimationFrame,
  onPoint = () => {},
  onState = () => {},
  onFollow = () => {},
  onStop = () => {},
}) {
  const manager = new ReplayManager({ timezone })
  const stepper = createStepper({ manager })
  let follow = null
  let starting = false
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
    if (coordinates) markerAt(coordinates)
  }

  function markerAt({ lon, lat }) {
    const data = {
      type: "Feature",
      geometry: { type: "Point", coordinates: [lon, lat] },
      properties: {},
    }
    const source = map.getSource(SOURCE)
    if (source) return source.setData(data)
    map.addSource(SOURCE, { type: "geojson", data })
    map.addLayer({
      id: PULSE,
      type: "circle",
      source: SOURCE,
      paint: {
        "circle-color": ORANGE,
        "circle-radius": ["interpolate", ["linear"], ["zoom"], 0, 10, 20, 50],
        "circle-opacity": 0.3,
      },
    })
    map.addLayer({
      id: LAYER,
      type: "circle",
      source: SOURCE,
      paint: {
        "circle-color": ORANGE,
        "circle-radius": ["interpolate", ["linear"], ["zoom"], 0, 8, 20, 24],
        "circle-stroke-width": 3,
        "circle-stroke-color": "#ffffff",
      },
    })
    map.on("click", LAYER, onMarkerClick)
  }

  function flyTo(point, fast) {
    const coordinates = manager.getCoordinates(point)
    if (!coordinates || !map.flyTo) return
    map.flyTo({
      center: [coordinates.lon, coordinates.lat],
      zoom: Math.max(map.getZoom?.() ?? 0, 14),
      duration: fast ? 100 : 500,
    })
  }

  function removeMarker() {
    if (map.getLayer(LAYER)) {
      map.off("click", LAYER, onMarkerClick)
      map.removeLayer(LAYER)
    }
    if (map.getLayer(PULSE)) map.removeLayer(PULSE)
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
    if (point) {
      marker(point)
      flyTo(point, true)
    }
    onState({ day: manager.getCurrentDay(), minute })
    return "ready"
  }

  function tick(time) {
    frame = null
    if (!playing || !opened) return
    last = time
    if (starting) {
      starting = false
      const point = stepper.start(Math.floor(minute), time)
      if (!point) return stop()
      marker(point)
      onPoint(point)
    } else {
      const step = stepper.frame(time)
      if (step.coords) {
        markerAt(step.coords)
        follow?.panTo(step.coords.lon, step.coords.lat)
      }
      if (step.point) {
        minute = step.minute
        onPoint(step.point)
        onState({
          day: manager.getCurrentDay(),
          minute,
          dayChanged: step.dayChanged,
        })
      }
      if (step.done) return stop()
    }
    frame = raf(tick)
  }

  function play() {
    if (!opened || frame !== null) return
    playing = true
    starting = true
    follow ??= createFollowCamera({ map, onChange: onFollow })
    follow.start()
    frame = raf(tick)
    onState({ day: manager.getCurrentDay(), minute })
  }

  function seek(value) {
    if (!opened) return
    minute = value
    const nearest = manager.findNearestMinuteWithPoints(value)
    const point = nearest === null ? null : manager.getPointAtPosition(nearest)
    if (point) {
      marker(point)
      flyTo(point, playing)
    }
    onPoint(point)
    onState({ day: manager.getCurrentDay(), minute, dayChanged: true })
    if (playing) starting = true
    return point
  }

  function setSpeed(value) {
    stepper.setSpeed(value, last ?? 0)
  }

  function stop() {
    const was = playing
    playing = false
    if (frame !== null) cancelRaf(frame)
    frame = null
    if (was) onStop()
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
    follow?.destroy()
    follow = null
    removeMarker()
  }

  return {
    open,
    setDate: open,
    play,
    pause: stop,
    seek,
    setSpeed,
    recenter: (lngLat) => {
      if (!opened) return
      follow ??= createFollowCamera({ map, onChange: onFollow })
      follow.start()
      const coordinates = manager.getCoordinates(
        manager.getPointAtPosition(manager.findNearestMinuteWithPoints(minute)),
      )
      follow.recenter(
        lngLat ?? (coordinates && [coordinates.lon, coordinates.lat]),
      )
    },
    reconnect,
    close,
    manager,
    get playing() {
      return playing
    },
  }
}
