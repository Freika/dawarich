import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { initializeAnalyticsEvents } from "./analytics_events.js"
import { hooks } from "./hooks/index.js"
import { Direct } from "./uploaders/direct.js"

const keepOpen = (from, to) => {
  const account = 'dialog,.navbar-end details:has([href="/users/sign_out"])'
  if (from.matches(account) && to.matches(account))
    to.toggleAttribute("open", from.hasAttribute("open"))
}

const liveSocket = new LiveSocket("/phoenix/live", Socket, {
  params: {
    _csrf_token: document.querySelector("meta[name=phoenix-csrf-token]")
      ?.content,
  },
  hooks,
  uploaders: { Direct },
  dom: { onBeforeElUpdated: keepOpen },
})

liveSocket.connect()
window.liveSocket = liveSocket

window.addEventListener("dawarich:flash-timeout", (event) => {
  setTimeout(() => event.target.querySelector("button")?.click(), 5000)
})

initializeAnalyticsEvents()

window.addEventListener("phx:close-dialog", (event) => {
  document.getElementById(event.detail.id)?.close()
})

window.addEventListener("dawarich:open-dialog", (event) => {
  event.target.showModal?.()
})

window.addEventListener("dawarich:close-dialog", (event) => {
  event.target.close?.()
})
