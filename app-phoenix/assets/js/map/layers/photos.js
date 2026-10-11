import { createPhotoLoader } from "../data/photo_loader.js"
import { createRequestScope } from "../data/request_scope.js"
import { createPhotoMarker } from "../ui/photo_marker.js"
import { BaseLayer } from "./base.js"
import { PhotoSpider } from "./photo_spider.js"

export class PhotosLayer extends BaseLayer {
  constructor(map, options) {
    super(map, { id: "photos", ...options })
    this.options = options
    this.markerCache = new Map()
    this.operations = createRequestScope(options.timers)
    this.loader = createPhotoLoader({
      ...options,
      onData: (data) => this.update(data),
    })
    this.spider = new PhotoSpider(map, (feature, position) =>
      this.createMarker(feature, position),
    )
    this.attached = false
    this.removed = false
    this.sync = () => this._syncMarkers()
    this.move = () => {
      this.operations.reset()
      this.spider._clearSpiderfiedMarkers()
      this._syncMarkers()
    }
    this.cluster = (event) => this.expand(event)
    this.enter = () => {
      map.getCanvas().style.cursor = "pointer"
    }
    this.leave = () => {
      map.getCanvas().style.cursor = ""
    }
    this.dataHandler = (event) => {
      if (event.sourceId === this.sourceId && event.isSourceLoaded) this.sync()
    }
    this.style = () => {
      if (!this.removed && !map.getSource(this.sourceId)) this.add(this.data)
    }
    map.on("style.load", this.style)
  }
  createMarker(feature, position) {
    return createPhotoMarker({
      ...this.options,
      map: this.map,
      feature,
      position,
      visible: this.visible,
    })
  }
  load(range, options) {
    return this.loader.load(range, options)
  }
  add(data = { type: "FeatureCollection", features: [] }) {
    if (this.removed) return
    super.add(data)
    if (!this.attached) {
      this.attached = true
      this.map.on("click", "photos-clusters", this.cluster)
      this.map.on("mouseenter", "photos-clusters", this.enter)
      this.map.on("mouseleave", "photos-clusters", this.leave)
      this.map.on("moveend", this.move)
      this.map.on("data", this.dataHandler)
    }
    this._syncMarkers()
  }
  update(data) {
    if (this.removed) return
    super.update(data)
    this._syncMarkers()
  }
  async expand(event) {
    if (this.removed || !this.visible) return
    this.operations.reset()
    const operation = this.operations.begin()
    try {
      const feature = this.map.queryRenderedFeatures(event.point, {
        layers: ["photos-clusters"],
      })[0]
      const source = this.map.getSource(this.sourceId)
      if (!feature || !source) return
      const id = feature.properties.cluster_id,
        center = feature.geometry.coordinates
      const zoom = await operation.wait(
        clusterRead(source, "getClusterExpansionZoom", [id]),
      )
      operation.check()
      if (zoom <= this.map.getMaxZoom()) this.map.easeTo({ center, zoom })
      else {
        const leaves = await operation.wait(
          clusterRead(source, "getClusterLeaves", [id, Infinity, 0]),
        )
        operation.check()
        if (leaves?.length) this.spider.expand(leaves, center)
      }
    } catch (error) {
      if (error.name !== "AbortError")
        this.options.onError?.("photo_cluster_failed")
    } finally {
      operation.close()
    }
  }
  getSourceConfig() {
    return {
      type: "geojson",
      data: this.data || { type: "FeatureCollection", features: [] },
      cluster: true,
      clusterRadius: 60,
      clusterMaxZoom: 15,
    }
  }
  getLayerConfigs() {
    return [
      {
        id: "photos-clusters",
        type: "circle",
        source: this.sourceId,
        filter: ["has", "point_count"],
        paint: {
          "circle-color": "rgba(59, 130, 246, 0.7)",
          "circle-radius": ["step", ["get", "point_count"], 20, 10, 25, 50, 30],
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
        },
      },
      {
        id: "photos-cluster-count",
        type: "symbol",
        source: this.sourceId,
        filter: ["has", "point_count"],
        layout: {
          "text-field": "{point_count_abbreviated}",
          "text-size": 14,
          "text-allow-overlap": true,
        },
        paint: {
          "text-color": "#ffffff",
        },
      },
    ]
  }
  getLayerIds() {
    return ["photos-clusters", "photos-cluster-count"]
  }
  _syncMarkers() {
    if (!this.visible) return

    const source = this.map.getSource(this.sourceId)
    if (!source) return
    const features = this.map.querySourceFeatures(this.sourceId, {
      filter: ["!", ["has", "point_count"]],
    })
    const seen = new Map()
    for (const feature of features) {
      const id =
        feature.properties.id ||
        `${feature.geometry.coordinates[0]}_${feature.geometry.coordinates[1]}`
      if (!seen.has(id)) {
        seen.set(id, feature)
      }
    }
    const bounds = this.map.getBounds()
    const visibleFeatures = new Map()
    for (const [id, feature] of seen) {
      const [lng, lat] = feature.geometry.coordinates
      if (bounds.contains([lng, lat])) {
        visibleFeatures.set(id, feature)
      }
    }
    const offsets = this.spider._computeSpiderOffsets(visibleFeatures)
    for (const [id, marker] of this.markerCache) {
      if (!visibleFeatures.has(id)) {
        marker.remove()
        this.markerCache.delete(id)
        this.spider._removeLeg(id)
      }
    }
    for (const [id, feature] of visibleFeatures) {
      const offset = offsets.get(id)
      const origin = feature.geometry.coordinates

      if (this.markerCache.has(id)) {
        if (offset) {
          this.markerCache.get(id).setLngLat(offset)
          this.spider._updateLeg(id, origin, offset)
        } else {
          this.markerCache.get(id).setLngLat(origin)
          this.spider._removeLeg(id)
        }
      } else {
        const lngLat = offset || origin
        const marker = this.createMarker(feature, lngLat)
        this.markerCache.set(id, marker)
        if (offset) {
          this.spider._updateLeg(id, origin, offset)
        }
      }
    }
  }
  show() {
    this.visible = true
    this.setVisibility(true)
    for (const marker of this.markerCache.values())
      marker.getElement().style.display = "block"
    for (const id of this.spider.legCache.values())
      if (this.map.getLayer(id))
        this.map.setLayoutProperty(id, "visibility", "visible")
    this._syncMarkers()
  }
  hide() {
    this.visible = false
    this.operations.reset()
    this.setVisibility(false)
    this.spider._clearSpiderfiedMarkers()
    for (const marker of this.markerCache.values())
      marker.getElement().style.display = "none"
    for (const id of this.spider.legCache.values())
      if (this.map.getLayer(id))
        this.map.setLayoutProperty(id, "visibility", "none")
  }
  remove() {
    if (this.removed) return
    this.removed = true
    this.loader.destroy()
    this.operations.destroy()
    this.spider.destroy()
    for (const marker of this.markerCache.values()) marker.remove()
    this.markerCache.clear()
    this.map.off("style.load", this.style)
    this.map.off("moveend", this.move)
    this.map.off("click", "photos-clusters", this.cluster)
    this.map.off("mouseenter", "photos-clusters", this.enter)
    this.map.off("mouseleave", "photos-clusters", this.leave)
    this.map.off("data", this.dataHandler)
    super.remove()
  }
}
function clusterRead(source, method, args) {
  return new Promise((resolve, reject) => {
    const pending = source[method](...args, (error, value) =>
      error ? reject(error) : resolve(value),
    )
    pending?.then?.(resolve, reject)
  })
}
