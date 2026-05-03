import maplibregl from "maplibre-gl"

export class HtmlLabelManager {
  constructor(map, options = {}) {
    this.map = map
    this.className = options.className || "map-html-label"
    this.anchor = options.anchor || "top"
    this.offset = options.offset || [0, 12]
    this.coordsFor = options.coordsFor || defaultCoordsFor
    this.idFor = options.idFor || defaultIdFor
    this.nameFor = options.nameFor || defaultNameFor
    this.visible = options.visible !== false
    this.markers = new Map()
    this._features = []
    this._filterFn = null
  }

  sync(features) {
    this._features = Array.isArray(features) ? features : []
    this._render()
  }

  setVisibility(visible) {
    this.visible = visible
    for (const marker of this.markers.values()) {
      this._applyVisibility(
        marker,
        visible && this._passesFilter(marker._feature),
      )
    }
  }

  setFilter(predicate) {
    this._filterFn = predicate
    for (const marker of this.markers.values()) {
      this._applyVisibility(
        marker,
        this.visible && this._passesFilter(marker._feature),
      )
    }
  }

  clear() {
    for (const marker of this.markers.values()) {
      marker.remove()
    }
    this.markers.clear()
    this._features = []
  }

  _render() {
    const seenIds = new Set()
    for (const feature of this._features) {
      const name = this.nameFor(feature)
      if (name == null || name === "") continue

      const coords = this.coordsFor(feature)
      if (!coords || coords.length < 2) continue

      const id = this.idFor(feature)
      if (id == null) continue
      seenIds.add(id)

      let marker = this.markers.get(id)
      if (marker) {
        marker.setLngLat(coords)
        const el = marker.getElement()
        if (el.textContent !== name) el.textContent = name
      } else {
        marker = this._createMarker(coords, name)
        this.markers.set(id, marker)
      }
      marker._feature = feature
      this._applyVisibility(marker, this.visible && this._passesFilter(feature))
    }
    for (const [id, marker] of this.markers) {
      if (!seenIds.has(id)) {
        marker.remove()
        this.markers.delete(id)
      }
    }
  }

  _createMarker(coords, name) {
    const el = document.createElement("div")
    el.className = this.className
    el.textContent = name
    return new maplibregl.Marker({
      element: el,
      anchor: this.anchor,
      offset: this.offset,
    })
      .setLngLat(coords)
      .addTo(this.map)
  }

  _applyVisibility(marker, visible) {
    const el = marker.getElement()
    el.style.display = visible ? "" : "none"
  }

  _passesFilter(feature) {
    if (!this._filterFn || !feature) return true
    return Boolean(this._filterFn(feature))
  }
}

function defaultCoordsFor(feature) {
  const props = feature?.properties || {}
  if (props.centerLng != null && props.centerLat != null) {
    return [props.centerLng, props.centerLat]
  }
  const geom = feature?.geometry
  if (geom?.type === "Point" && Array.isArray(geom.coordinates)) {
    return geom.coordinates
  }
  return null
}

function defaultIdFor(feature) {
  return feature?.properties?.id ?? null
}

function defaultNameFor(feature) {
  return feature?.properties?.name ?? null
}
