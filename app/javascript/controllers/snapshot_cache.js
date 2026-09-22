// Pure localStorage-backed cache for rendered achievement map snapshots.
// Storage and clock are injected so the logic is unit-testable without a DOM.
// Bump the version segment to invalidate every cached image at once.
export const CACHE_PREFIX = "ach-map:v3:"

export function readCache(store, key) {
  if (!store) return null
  const raw = store.getItem(key)
  if (!raw) return null
  try {
    return JSON.parse(raw)
  } catch {
    store.removeItem(key)
    return null
  }
}

export function writeCache(store, key, value, now) {
  if (!store) return
  const payload = JSON.stringify({ ...value, t: now })
  try {
    store.setItem(key, payload)
  } catch {
    evictOldest(store)
    try {
      store.setItem(key, payload)
    } catch {
      // Still no room even after eviction — skip caching this snapshot.
    }
  }
}

export function evictOldest(store) {
  const entries = []
  for (let i = 0; i < store.length; i++) {
    const k = store.key(i)
    if (!k?.startsWith(CACHE_PREFIX)) continue
    let t = 0
    try {
      t = JSON.parse(store.getItem(k)).t || 0
    } catch {
      /* unreadable entry sorts oldest and gets dropped first */
    }
    entries.push([k, t])
  }
  entries.sort((a, b) => a[1] - b[1])
  const drop = Math.max(1, Math.floor(entries.length / 4))
  for (let i = 0; i < drop; i++) store.removeItem(entries[i][0])
}
