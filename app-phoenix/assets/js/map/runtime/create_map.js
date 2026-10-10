import { createLifecycle } from "./lifecycle.js"
import { createOperations } from "./operation.js"

export function createMapRuntime({
  element,
  config,
  reader,
  loadLibrary,
  loadStyle,
  attach,
  refresh = async () => {},
  events = {},
}) {
  const lifetime = createLifecycle()
  const operations = createOperations()
  let current = config
  let map = null
  let mounting = null
  let state = "idle"
  lifetime.own(() => reader.destroy())

  function destroy() {
    operations.destroy()
    lifetime.destroy()
    map = null
    if (state !== "failed") state = "cancelled"
  }

  async function runRefresh() {
    if (lifetime.destroyed) return "cancelled"
    const operation = operations.begin()
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
      events.refreshed?.({ revision: current.revision ?? operation.revision })
      return "ready"
    } catch (error) {
      if (error.name === "AbortError") return "cancelled"
      events.error?.({ code: "map_refresh_failed" })
      return "failed"
    } finally {
      operation.close()
    }
  }

  async function initialize() {
    const operation = operations.begin()
    state = "loading"
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
      map = new library.Map({ ...current.mapOptions, container: root, style })
      const owned = map
      lifetime.own(() => owned.remove())
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
      state = "ready"
      return await runRefresh()
    } catch (error) {
      if (error.name === "AbortError") return "cancelled"
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
      operations.reset()
      reader.reset()
      if (!map) mounting = null
      return map ? runRefresh() : this.mount()
    },
    async reconnect() {
      if (lifetime.destroyed) return "cancelled"
      reader.reset()
      if (map) operations.reset()
      return map ? runRefresh() : this.mount()
    },
    destroy,
    get map() {
      return map
    },
    get state() {
      return state
    },
    get config() {
      return current
    },
  }
}
