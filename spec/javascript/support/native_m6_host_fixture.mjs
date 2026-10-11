import { mountHost } from "../../../app-phoenix/assets/js/map/runtime/host.js"

export class Element {
  constructor() {
    this.listeners = new Map()
    this.style = { setProperty() {} }
    this.dataset = {}
    this.children = []
  }
  addEventListener(name, fn) {
    if (!this.listeners.has(name)) this.listeners.set(name, new Set())
    this.listeners.get(name).add(fn)
  }
  removeEventListener(name, fn) {
    this.listeners.get(name)?.delete(fn)
  }
  emit(name, value = {}) {
    value.target ??= this
    for (const fn of this.listeners.get(name) ?? []) fn(value)
    if (name === "click") this.parent?.emit(name, value)
  }
  closest(selector) {
    return selector === this.selector ? this : this.parent?.closest(selector)
  }
  appendChild(child) {
    this.children.push(child)
  }
  replaceChildren(...children) {
    this.children = children
  }
  setAttribute(key, value) {
    this[key] = value
  }
  append(...children) {
    this.children.push(...children)
  }
  getBoundingClientRect() {
    return { left: 0, right: 800, top: 0, bottom: 600, width: 800, height: 600 }
  }
  remove() {}
}

export function fixture(config = {}, options = {}) {
  const nodes = new Map()
  const root = new Element()
  root.querySelector = (selector) => nodes.get(selector)
  const setNode = nodes.set.bind(nodes)
  nodes.set = (selector, node) => {
    node.parent = root
    node.selector = selector
    return setNode(selector, node)
  }
  const element = new Element()
  const range = {
    startAt: "2026-03-29T00:00",
    endAt: "2026-03-29T23:59",
    timezone: "Europe/Berlin",
  }
  element.dataset.mapConfig = JSON.stringify({ range, ...config })
  element.closest = () => root
  element.ownerDocument = { createElement: () => new Element() }
  root.ownerDocument = element.ownerDocument
  const listeners = new Map(),
    sources = new Map(),
    layers = new Map(),
    pushed = [],
    reads = []
  const toggle = () => ({
    enabled: true,
    enable() {
      this.enabled = true
    },
    disable() {
      this.enabled = false
    },
    isEnabled() {
      return this.enabled
    },
  })
  const map = {
    dragPan: toggle(),
    boxZoom: toggle(),
    on(name, id, fn) {
      const key = fn ? `${name}:${id}` : name
      if (!listeners.has(key)) listeners.set(key, new Set())
      listeners.get(key).add(fn ?? id)
    },
    once(name, fn) {
      this.on(name, fn)
    },
    off(name, id, fn) {
      listeners.get(fn ? `${name}:${id}` : name)?.delete(fn ?? id)
    },
    emit(name, value = {}) {
      for (const fn of [...(listeners.get(name) ?? [])]) fn(value)
    },
    addSource(id, source) {
      sources.set(id, {
        ...source,
        setData(data) {
          this.data = data
        },
      })
    },
    getSource(id) {
      return sources.get(id)
    },
    removeSource(id) {
      sources.delete(id)
    },
    addLayer(layer) {
      layers.set(layer.id, layer)
    },
    getLayer(id) {
      return layers.get(id)
    },
    removeLayer(id) {
      layers.delete(id)
    },
    getStyle() {
      return { layers: [...layers.values()] }
    },
    setFilter(id, filter) {
      if (layers.has(id)) layers.get(id).filter = filter
    },
    getFilter(id) {
      return layers.get(id)?.filter
    },
    setLayoutProperty() {},
    setPaintProperty() {},
    refreshTiles() {},
    getZoom: () => 12,
    loaded: () => true,
    getContainer: () => element,
    getCanvas: () => ({ style: {} }),
    remove() {},
    getBounds: () => ({
      getSouth: () => 51,
      getNorth: () => 53,
      getWest: () => 12,
      getEast: () => 14,
    }),
  }
  const reader = {
    async read(resource, params) {
      reads.push({ resource, params })
      return {
        data: {
          type: "Feature",
          geometry: {
            type: "LineString",
            coordinates: [
              [12, 51],
              [14, 53],
            ],
          },
          properties: {},
        },
      }
    },
    reset() {},
    destroy() {},
    async pages(resource, params) {
      reads.push({ resource, params })
      return []
    },
  }
  const owner = mountHost({
    element,
    reader,
    pushEvent: (event, payload, reply) =>
      pushed.push({ event, payload, reply }),
    loadStyle: async () => ({ version: 8 }),
    loadLibrary: async () => ({
      ...options.library,
      Map: function NativeMap() {
        return map
      },
    }),
  })
  return {
    owner,
    element,
    root,
    nodes,
    map,
    sources,
    layers,
    listeners,
    pushed,
    reads,
    reader,
  }
}
