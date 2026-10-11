export function createReplayDensity({ container, document, manager, seek }) {
  let bindings = []
  function clear() {
    for (const [bar, click] of bindings) bar.removeEventListener("click", click)
    bindings = []
    container.replaceChildren()
  }
  function render() {
    clear()
    container.append(
      ...manager.getDataDensity(48).map((value, index) => {
        const bar = document.createElement("button")
        bar.type = "button"
        bar.className = "flex-1 min-w-0 h-3 bg-primary rounded-sm"
        bar.style.opacity = value > 0 ? (value > 0.5 ? "1" : "0.5") : "0.1"
        bar.dataset.density = String(value)
        const minute = Math.floor(
          (manager.getCurrentDayLengthMinutes() * index) / 48,
        )
        bar.setAttribute("aria-label", manager.formatCurrentMinute(minute))
        const click = () => seek(minute)
        bar.addEventListener("click", click)
        bindings.push([bar, click])
        return bar
      }),
    )
  }
  render()
  return { render, destroy: clear }
}
