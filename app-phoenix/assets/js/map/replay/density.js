export function createReplayDensity({ container, document, manager }) {
  function render() {
    container.replaceChildren(
      ...manager.getDataDensity(48).map((value) => {
        const bar = document.createElement("div")
        bar.className = "replay-density-bar"
        if (value > 0) bar.classList.add("has-data")
        if (value > 0.5) bar.classList.add("high-density")
        return bar
      }),
    )
  }
  render()
  return { render, destroy: () => container.replaceChildren() }
}
