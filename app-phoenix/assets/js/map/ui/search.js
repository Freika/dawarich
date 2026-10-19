const DEBOUNCE_MS = 300

export function createSearchUi({
  input,
  results,
  document,
  search,
  onSelect,
  onCancel = () => {},
  timers = globalThis,
  debounceMs = DEBOUNCE_MS,
}) {
  let timer = null
  let items = []
  let active = -1
  let destroyed = false

  function render() {
    results.replaceChildren(
      ...items.map((item, index) => {
        const option = document.createElement("li")
        option.textContent = item.name
        option.setAttribute("role", "option")
        option.setAttribute("aria-selected", String(index === active))
        option.addEventListener("click", () => select(index))
        return option
      }),
    )
    results.classList.toggle("hidden", items.length === 0)
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
    onSelect(item)
  }

  const onInput = () => {
    clearTimer()
    const query = input.value
    timer = timers.setTimeout(async () => {
      timer = null
      const result = await search.suggest(query)
      if (destroyed || result.status !== "ok") return
      items = result.suggestions
      active = -1
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
    } else if (event.key === "Enter" && active >= 0) {
      event.preventDefault()
      select(active)
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
