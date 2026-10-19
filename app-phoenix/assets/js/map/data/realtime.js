import { createRefresh } from "./refresh.js"

const kinds = new Set([
  "map",
  "points",
  "tracks",
  "imports",
  "map_edits",
  "family",
  "public",
  "trip",
  "progress",
  "reconnect",
])
const delays = { points: 1000, tracks: 1000, family: 1000, reconnect: 1000 }
export function createRealtime({
  run,
  timers = globalThis,
  document = globalThis.document,
}) {
  const pending = new Set(),
    seen = new Map()
  const hidden = () => document?.visibilityState === "hidden"
  const refresh = createRefresh({
    timers,
    delay: () =>
      pending.size
        ? Math.min(...[...pending].map((kind) => delays[kind] ?? 0))
        : 0,
    run: () => {
      if (hidden()) return "deferred"
      const batch = { kinds: [...pending] }
      pending.clear()
      return run(batch)
    },
  })
  const schedule = () =>
    hidden() ? Promise.resolve("deferred") : refresh.schedule()
  const visible = () => {
    if (!hidden() && pending.size > 0) refresh.schedule()
  }
  document?.addEventListener?.("visibilitychange", visible)
  return {
    invalidate(receipt = {}) {
      const kind = receipt.kind ?? "map"
      if (!kinds.has(kind)) return Promise.resolve("ignored")
      if (receipt.revision !== undefined) {
        const revision = receipt.revision
        if (
          !Number.isSafeInteger(revision) ||
          revision < 1 ||
          revision <= (seen.get(kind) ?? 0)
        )
          return Promise.resolve("ignored")
        seen.set(kind, revision)
      }
      pending.add(kind)
      return schedule()
    },
    reconnect: () => {
      pending.add("reconnect")
      return schedule()
    },
    destroy: () => {
      document?.removeEventListener?.("visibilitychange", visible)
      pending.clear()
      refresh.destroy()
    },
  }
}
