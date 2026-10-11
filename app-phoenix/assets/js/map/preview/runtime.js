import { createPreviewGate, documentPreviewGate } from "./gate.js"
import { createPreviewOwner } from "./owner.js"
export { createPreviewGate }
export function mountPreview({
  element,
  gate = documentPreviewGate(element.ownerDocument),
  createOwner = createPreviewOwner,
  observe = (root, changed) => {
    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) changed(entry.isIntersecting)
    })
    observer.observe(root)
    return () => observer.disconnect()
  },
}) {
  let config = JSON.parse(element.dataset.mapConfig ?? "{}"),
    visible = false,
    destroyed = false,
    stop,
    pending,
    owner,
    release
  function clear() {
    pending?.abort()
    pending = null
    owner?.destroy()
    owner = null
    release?.()
    release = null
  }
  async function visibility(next) {
    visible = next
    if (!visible || destroyed) {
      clear()
      return
    }
    if (pending || owner) return
    const request = new AbortController()
    pending = request
    let acquired
    try {
      acquired = await gate.acquire(request.signal)
      if (destroyed || !visible || request.signal.aborted) {
        acquired()
        return
      }
      release = acquired
      owner = createOwner({ element, config })
      await owner.mount()
    } catch {
      if (!request.signal.aborted) {
        clear()
        element.dataset.mapState = "failed"
      } else acquired?.()
    } finally {
      if (pending === request) pending = null
    }
  }
  return {
    mount() {
      if (!destroyed && !stop) stop = observe(element, visibility)
    },
    update(next) {
      config = next
      return owner?.update(next)
    },
    reconnect() {
      return owner?.reconnect()
    },
    destroy() {
      if (destroyed) return
      destroyed = true
      stop?.()
      clear()
    },
  }
}
