import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { hooks } from "./hooks/index.js"
import { Direct } from "./uploaders/direct.js"

const csrfToken = document
  .querySelector("meta[name='phoenix-csrf-token']")
  ?.getAttribute("content")

const keepOpen = (fromEl, toEl) => {
  if (fromEl.matches("details, dialog") && toEl.matches("details, dialog"))
    toEl.toggleAttribute("open", fromEl.hasAttribute("open"))
}

const liveSocket = new LiveSocket("/phoenix/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks,
  uploaders: { Direct },
  dom: { onBeforeElUpdated: keepOpen },
})

liveSocket.connect()
window.liveSocket = liveSocket

window.addEventListener("dawarich:flash-timeout", (event) => {
  window.setTimeout(() => event.target.querySelector("button")?.click(), 5000)
})

window.addEventListener("dawarich:track", (event) => {
  if (typeof window.sa_event === "function") window.sa_event(event.detail.event)
})

window.addEventListener("phx:close-dialog", (event) => {
  document.getElementById(event.detail.id)?.close()
})
