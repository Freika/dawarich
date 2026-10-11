import { attachViewportStore } from "../data/view_store.js"
import { installStyleFallback } from "../style/load_style.js"
import { registerRTLTextPlugin } from "../style/rtl.js"
import { createLifecycle } from "./lifecycle.js"
import { createOperations } from "./operation.js"

export function createMapRuntime({
  element,
  config,
  reader,
  loadLibrary,
  loadStyle,
  transformRequest,
  attach,
  refresh = async () => {},
  events = {},
  timers = globalThis,
}) {
  const lifetime = createLifecycle()
  const operations = createOperations(timers)
  let current = config
  let map = null
  let attached = false
  let viewport = null
  let mounting = null
  let state = "idle"
  let presentationState = "idle"
  lifetime.own(() => reader.destroy())
  const window = element.ownerDocument.defaultView
  const retire = (event) => {
    if (!event.persisted) destroy()
  }
  window?.addEventListener("pagehide", retire)
  lifetime.own(() => window?.removeEventListener("pagehide", retire))

  function publish(value) {
    presentationState = value
    if (element.dataset) element.dataset.mapState = value
    const loading = element.querySelector?.("[data-map-loading]")
    if (loading) loading.hidden = value !== "loading"
  }

  function destroy() {
    operations.destroy()
    lifetime.destroy()
    map = null
    if (state !== "failed") state = "cancelled"
    publish(state)
  }

  async function runRefresh() {
    if (lifetime.destroyed) return "cancelled"
    const operation = operations.begin()
    publish("loading")
    events.loading?.({ revision: current.revision ?? operation.revision })
    try {
      await operation.wait(
        refresh({
          map,
          config: current,
          reader,
          operation,
          signal: operation.signal,
        }),
      )
      operation.check()
      publish("ready")
      events.refreshed?.({ revision: current.revision ?? operation.revision })
      return "ready"
    } catch (error) {
      if (
        error.name === "AbortError" &&
        (lifetime.destroyed || operation.revision !== operations.revision)
      )
        return "cancelled"
      publish("failed")
      events.error?.({ code: "map_refresh_failed" })
      return "failed"
    } finally {
      operation.close()
    }
  }

  async function initialize() {
    const operation = operations.begin()
    state = "loading"
    publish("loading")
    try {
      const library = await operation.wait(
        loadLibrary({ signal: operation.signal }),
      )
      operation.check()
      const style = await operation.wait(
        loadStyle(current, { signal: operation.signal }),
      )
      operation.check()
      const root = element.ownerDocument.createElement("div")
      Object.assign(root.style, { width: "100%", height: "100%" })
      element.appendChild(root)
      lifetime.own(() => root.remove())
      map = new library.Map({
        center: [0, 0],
        zoom: 2,
        ...current.mapOptions,
        container: root,
        style,
        transformRequest,
      })
      const owned = map
      lifetime.own(() => owned.remove())
      const Observer =
        element.ownerDocument.defaultView?.ResizeObserver ??
        globalThis.ResizeObserver
      if (Observer) {
        const observer = new Observer(() => {
          if (!lifetime.destroyed) owned.resize()
        })
        observer.observe(element)
        lifetime.own(() => observer.disconnect())
      }
      if (
        current.navigationControls !== false &&
        typeof library.NavigationControl === "function"
      )
        map.addControl(new library.NavigationControl(), "top-right")
      if (typeof library.getRTLTextPluginStatus === "function")
        void registerRTLTextPlugin(
          library,
          current.rtlUrl ?? "/assets/mapbox-gl-rtl-text.js",
          { onError: (code) => events.error?.({ code }) },
        )
      if (typeof map.on === "function") {
        const fallback = installStyleFallback({
          map,
          getConfig: () => current,
          load: loadStyle,
        })
        lifetime.own(fallback.destroy)
      }
      if (current.namespace && typeof map.jumpTo === "function") {
        viewport = attachViewportStore({
          map,
          namespace: current.namespace,
          fallback: current.mapOptions,
        })
        lifetime.own(viewport.destroy)
        viewport.restore()
      }
      const pending = Promise.resolve(
        attach?.({
          map,
          config: current,
          reader,
          lifetime,
          operation,
          signal: operation.signal,
        }),
      )
      let released = false
      const release = (cleanup) => {
        if (released) return
        released = true
        try {
          cleanup?.()
        } catch {}
      }
      pending.then(
        (cleanup) => {
          if (operation.signal.aborted) release(cleanup)
        },
        () => {},
      )
      try {
        const cleanup = await operation.wait(pending)
        operation.check()
        lifetime.own(() => release(cleanup))
      } catch (error) {
        pending.then(release, () => {})
        throw error
      }
      const { installMapDiagnostics } = await operation.wait(
        import("./diagnostics.js"),
      )
      operation.check()
      lifetime.own(
        installMapDiagnostics({ element, map, getConfig: () => current }),
      )
      attached = true
      state = "ready"
      return await runRefresh()
    } catch (error) {
      if (error.name === "AbortError") {
        if (operation.revision === operations.revision) destroy()
        return "cancelled"
      }
      state = "failed"
      destroy()
      events.error?.({ code: "map_initialization_failed" })
      return "failed"
    } finally {
      operation.close()
    }
  }

  return {
    mount() {
      if (lifetime.destroyed) return Promise.resolve(state)
      if (!mounting) mounting = initialize()
      return mounting
    },
    async update(next) {
      if (lifetime.destroyed) return "cancelled"
      current = next
      viewport?.updateNamespace(next.namespace)
      if (map && !attached) return mounting
      operations.reset()
      reader.reset()
      if (!map) mounting = null
      return map ? runRefresh() : this.mount()
    },
    async reconnect() {
      if (lifetime.destroyed) return "cancelled"
      if (map && !attached) return mounting
      reader.reset()
      if (map) operations.reset()
      return map ? runRefresh() : this.mount()
    },
    destroy,
    get map() {
      return map
    },
    get presentationState() {
      return presentationState
    },
    get state() {
      return state
    },
    get config() {
      return current
    },
  }
}
