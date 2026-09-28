import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

const meta = (name) =>
  document.querySelector(`meta[name='${name}']`)?.getAttribute("content")

const liveSocket = new LiveSocket("/phoenix/live", Socket, {
  params: { _csrf_token: meta("phoenix-csrf-token") },
  hooks: {},
})
liveSocket.connect()
window.liveSocket = liveSocket

const removeFlash = (flash) => flash.remove()

const scheduleFlashRemoval = () => {
  document
    .querySelectorAll("[data-removals-timeout-value='5000']")
    .forEach((flash) => window.setTimeout(() => removeFlash(flash), 5000))
}

document.addEventListener("DOMContentLoaded", scheduleFlashRemoval)
document.addEventListener("phx:page-loading-stop", scheduleFlashRemoval)
document.addEventListener("click", (event) => {
  const button = event.target.closest("[data-action='click->removals#remove']")
  if (button) removeFlash(button.closest("[role='alert']"))
})
