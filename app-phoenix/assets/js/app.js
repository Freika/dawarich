import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { hooks } from "./hooks/index.js"

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
  dom: { onBeforeElUpdated: keepOpen },
})

liveSocket.connect()
window.liveSocket = liveSocket
