export function initializeHttpCredentialQr(
  el,
  load = () => import("../hooks/credential_qr.js"),
) {
  let generation = 0
  let stopped = false
  let hook
  const clear = () => {
    generation += 1
    hook?.clear()
  }
  const reveal = async () => {
    const expected = ++generation
    try {
      const { CredentialQr } = await load()
      if (stopped || expected !== generation) return
      if (!hook) {
        hook = Object.assign(Object.create(CredentialQr), { el })
        hook.mounted()
      }
      hook.reveal()
    } catch {
      clear()
    }
  }
  const dialog = el.closest("dialog")
  el.addEventListener("dawarich:http-reveal-qr", reveal)
  dialog?.addEventListener("close", clear)
  return () => {
    stopped = true
    clear()
    hook?.destroyed()
    el.removeEventListener("dawarich:http-reveal-qr", reveal)
    dialog?.removeEventListener("close", clear)
  }
}
