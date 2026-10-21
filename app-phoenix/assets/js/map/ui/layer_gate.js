import { Toast } from "./toast.js"

export async function startLayerPreview({ layerName, toggle, showFn, hideFn, onEnd, translate, toast = Toast, timers = globalThis }) {
  const node = toast.info(translate("layer_preview.started", { layer: layerName, seconds: 20 }), 0)
  let remaining = 20, timeout, stopped = false
  const interval = timers.setInterval(() => {
    remaining -= 5
    if (remaining > 0 && node?.parentNode)
      node.textContent = translate("layer_preview.remaining", { layer: layerName, seconds: remaining })
  }, 5000)
  const cancel = () => {
    if (stopped) return
    stopped = true
    timers.clearInterval(interval)
    timers.clearTimeout(timeout)
  }
  try {
    await showFn()
    if (stopped) return cancel
    timeout = timers.setTimeout(() => {
      cancel()
      toast.dismiss(node)
      hideFn()
      toggle.checked = false
      onEnd?.()
    }, 20000)
  } catch {
    cancel()
    toast.dismiss(node)
    toggle.checked = false
  }
  return cancel
}
