import { eraseFamily, erasePublic } from "./shared_erase.js"

function lazyMap(load, name, events, clear, erase, reload) {
  return {
    mounted() {
      this.alive = true
      this.pending = new Map()
      this.callbacks = new Map()
      this.listeners = events.map((event) =>
        this.handleEvent(event, (data) => {
          if (event === clear) {
            this.pending.clear()
            erase(this.el)
          }
          if (this.runtime) this.callbacks.get(event)?.(data)
          else this.pending.set(event, data)
        }),
      )
      this.ready = (this.loadRuntime || load)()
        .then((module) => {
          if (!this.alive) return
          const runtime = {
            ...module[name],
            el: this.el,
            pushEvent: (...args) => this.pushEvent(...args),
            handleEvent: (event, callback) => {
              this.callbacks.set(event, callback)
              return event
            },
            removeHandleEvent: (event) => this.callbacks.delete(event),
          }
          runtime.mounted()
          this.runtime = runtime
          for (const [event, data] of this.pending)
            this.callbacks.get(event)?.(data)
          this.pending.clear()
        })
        .catch(() => {
          this.pending.clear()
          erase(this.el)
        })
    },
    disconnected() {
      this.pending.clear()
      this.runtime?.disconnected()
      erase(this.el)
    },
    reconnected() {
      this.pushEvent(reload, {})
    },
    destroyed() {
      this.alive = false
      this.pending.clear()
      this.runtime?.destroyed()
      for (const ref of this.listeners) this.removeHandleEvent(ref)
      this.listeners = []
      this.callbacks.clear()
      erase(this.el)
    },
  }
}

export const SharedMap = lazyMap(
  () => import("./shared_map.js"),
  "SharedMap",
  ["public-share-snapshot", "public-share-clear"],
  "public-share-clear",
  erasePublic,
  "public_reload",
)

export const FamilyMap = lazyMap(
  () => import("./family_map.js"),
  "FamilyMap",
  ["family-locations", "family-clear", "family-focus"],
  "family-clear",
  eraseFamily,
  "family_reload",
)
