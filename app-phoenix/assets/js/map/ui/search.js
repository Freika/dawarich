const DEBOUNCE_MS = 300
const MIN_LENGTH = 2
const ROW =
  "search-result-item p-3 hover:bg-base-200 cursor-pointer rounded-lg transition-colors"

export function createSearchUi({
  input,
  results,
  document,
  search,
  onSelect,
  onCancel = () => {},
  translate = (key) => key,
  timers = globalThis,
  debounceMs = DEBOUNCE_MS,
}) {
  let timer = null
  let items = []
  let active = -1
  let destroyed = false

  const node = (className, text) => {
    const element = document.createElement("div")
    element.className = className
    if (text != null) element.textContent = text
    return element
  }

  function show(...children) {
    results.replaceChildren(...children)
    results.classList.toggle("hidden", children.length === 0)
  }

  function row(item, index) {
    const element = node(index === active ? `${ROW} bg-base-200` : ROW)
    element.setAttribute("data-lat", item.lat)
    element.setAttribute("data-lon", item.lon)
    element.append(
      node(
        "font-medium text-sm",
        item.name || translate("search.unknown_location"),
      ),
    )
    if (item.address)
      element.append(node("text-xs text-base-content/60 mt-1", item.address))
    element.addEventListener("click", () => select(index))
    return element
  }

  function render() {
    show(...items.map(row))
  }

  function loading() {
    const element = node(
      "p-3 text-sm text-base-content/60 flex items-center gap-2",
    )
    element.append(node("loading loading-spinner loading-sm"))
    element.append(translate("search.searching"))
    show(element)
  }

  function clearTimer() {
    if (timer !== null) timers.clearTimeout(timer)
    timer = null
  }

  function reset() {
    clearTimer()
    items = []
    active = -1
    render()
  }

  function select(index) {
    const item = items[index]
    if (!item || destroyed) return
    reset()
    input.value = item.name || ""
    onSelect(item)
  }

  const onInput = () => {
    clearTimer()
    const query = input.value
    if (String(query || "").trim().length < MIN_LENGTH) {
      search.cancel()
      return reset()
    }
    timer = timers.setTimeout(async () => {
      timer = null
      loading()
      const result = await search.suggest(query)
      if (destroyed || result.status === "stale") return
      if (result.status !== "ok")
        return show(
          node(
            "p-3 text-sm text-error",
            translate("search.suggestions_failed"),
          ),
        )
      items = result.suggestions
      active = -1
      if (items.length === 0)
        return show(
          node(
            "p-3 text-sm text-base-content/60",
            translate("search.no_locations"),
          ),
        )
      render()
    }, debounceMs)
  }

  const onKeydown = (event) => {
    if (event.key === "Escape") {
      event.preventDefault()
      search.cancel()
      input.value = ""
      reset()
      onCancel()
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      if (items.length === 0) return
      const step = event.key === "ArrowDown" ? 1 : -1
      active = (active + step + items.length) % items.length
      render()
    } else if (event.key === "Enter" && items.length > 0) {
      event.preventDefault()
      select(Math.max(active, 0))
    }
  }

  input.addEventListener("input", onInput)
  input.addEventListener("keydown", onKeydown)

  function destroy() {
    if (destroyed) return
    destroyed = true
    clearTimer()
    search.cancel()
    input.removeEventListener("input", onInput)
    input.removeEventListener("keydown", onKeydown)
  }

  return { destroy, reset }
}
