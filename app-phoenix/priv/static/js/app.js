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
