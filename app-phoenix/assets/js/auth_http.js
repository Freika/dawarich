import { initializeAuthForms } from "./http/auth_forms.js"

let dispose
const mount = () => {
  dispose?.()
  dispose = initializeAuthForms()
}
window.addEventListener("pageshow", mount)
window.addEventListener("pagehide", () => dispose?.())
mount()
