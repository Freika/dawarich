export function createOnboardingDialog({
  dialog,
  auto,
  userId,
  storage = globalThis.localStorage,
  timers = globalThis,
  complete,
}) {
  const key = userId
    ? `dawarich_onboarding_shown_${userId}`
    : "dawarich_onboarding_shown"
  let timer = null
  let onClose = null
  let destroyed = false

  const read = () => {
    try {
      return storage?.getItem(key)
    } catch (_error) {
      return null
    }
  }

  const write = () => {
    try {
      storage?.setItem(key, "true")
    } catch (_error) {}
  }

  function release() {
    if (onClose) dialog.removeEventListener("close", onClose)
    onClose = null
  }

  function show() {
    timer = null
    if (destroyed || read() || dialog.open) return
    dialog.showModal()
    if (!dialog.open) return
    write()
    onClose = () => {
      release()
      if (!destroyed) complete()
    }
    dialog.addEventListener("close", onClose)
  }

  function start() {
    if (auto && !destroyed && timer === null) timer = timers.setTimeout(show, 0)
  }

  function destroy() {
    destroyed = true
    if (timer !== null) timers.clearTimeout(timer)
    timer = null
    release()
  }

  return { start, destroy }
}
