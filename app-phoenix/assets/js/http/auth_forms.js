export function initializeAuthForms(doc = document, win = window) {
  const forms = [...doc.querySelectorAll("form[data-auth-form]")]
  const accepted = new WeakSet()
  const controls = (form) =>
    form.querySelectorAll('button[type="submit"], input[type="submit"]')
  const reset = () => {
    for (const form of forms) {
      accepted.delete(form)
      form.removeAttribute("aria-busy")
      for (const button of controls(form))
        button.removeAttribute("aria-disabled")
    }
  }
  const submit = (event) => {
    if (event.defaultPrevented) return
    const form = event.currentTarget
    if (accepted.has(form)) {
      event.preventDefault()
      return
    }
    if (!form.checkValidity()) {
      event.preventDefault()
      return
    }
    accepted.add(form)
    form.setAttribute("aria-busy", "true")
    for (const button of controls(form))
      button.setAttribute("aria-disabled", "true")
  }
  for (const form of forms) form.addEventListener("submit", submit)
  win.addEventListener("pageshow", reset)
  doc.querySelector("[data-auth-error-summary]")?.focus()
  return () => {
    reset()
    for (const form of forms) form.removeEventListener("submit", submit)
    win.removeEventListener("pageshow", reset)
  }
}
