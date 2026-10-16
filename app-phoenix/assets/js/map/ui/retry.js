export function createMapRetry({ root, translate, run }) {
  let current, destroyed = false
  function fail(code) {
    if (destroyed || !root?.ownerDocument) return
    if (current?.code === code) return
    current?.node.remove()
    const document = root.ownerDocument
    const node = document.createElement("div")
    node.setAttribute("role", "alert")
    node.dataset.mapRetry = code
    Object.assign(node.style, {
      position: "absolute", left: "1rem", top: "1rem", zIndex: "40",
      maxWidth: "calc(100% - 2rem)", pointerEvents: "none",
      overflowWrap: "anywhere", whiteSpace: "normal",
    })
    node.className = "alert alert-error"
    const message = document.createElement("span")
    message.textContent = translate(code.startsWith("scratch")
      ? "messages.failed_to_load_visited_countries" : "messages.failed_to_load_map_tiles")
    const button = document.createElement("button")
    button.type = "button"
    button.className = "btn btn-sm whitespace-normal shrink-0"
    button.style.pointerEvents = "auto"
    button.textContent = translate("messages.retry")
    const entry = { code, node }
    button.addEventListener("click", async () => {
      if (destroyed || current !== entry || button.disabled) return
      button.disabled = true
      try {
        const result = await run(code)
        if (result === "failed") throw new Error("retry_failed")
        if (current === entry) { node.remove(); current = null }
      } catch {
        button.disabled = false
      }
    })
    node.append(message, button)
    root.append(node)
    current = entry
  }
  return { fail, destroy() { destroyed = true; current?.node.remove(); current = null } }
}
