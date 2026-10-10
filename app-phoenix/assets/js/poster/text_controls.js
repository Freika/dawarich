const TEXT_FIELDS = ["title", "subtitle", "coords", "font"]

export function bindTextControls({ root, find, on, studio, ensureFont }) {
  const toggle = find("text-toggle")
  const layers = [...root.querySelectorAll("[data-poster-layer]")]
  const tokens = [...root.querySelectorAll("[data-poster-token]")]
  const tokenValues = [...root.querySelectorAll("[data-poster-token-value]")]
  let seededTokens = null

  const label = (name, value) => {
    const element = find(`${name}-label`)
    if (element) element.textContent = `${value}%`
  }
  const tokenLabel = (input) => {
    const element = tokenValues.find(
      (candidate) =>
        candidate.dataset.posterTokenValue === input.dataset.posterToken,
    )
    if (element) element.textContent = input.value.toUpperCase()
  }

  on(toggle, "change", () => {
    for (const name of TEXT_FIELDS) {
      const field = find(name)
      if (field) field.disabled = !toggle.checked
    }
    studio.update({ textEnabled: toggle.checked })
  })
  for (const name of ["title", "subtitle"]) {
    const field = find(name)
    on(field, "input", () => studio.update({ [name]: field.value }))
  }
  on(find("coords"), "change", () =>
    studio.update({ coords: find("coords").checked }),
  )
  on(find("font"), "change", () => {
    const key = find("font").value
    studio.update({ fontKey: key })
    ensureFont?.(key).then(() => studio.redraw())
  })
  for (const layer of layers) {
    on(layer, "change", () =>
      studio.update({
        hidden: new Set(
          layers
            .filter((toggleInput) => !toggleInput.checked)
            .map((toggleInput) => toggleInput.dataset.posterLayer),
        ),
      }),
    )
  }
  for (const name of ["opacity", "width"]) {
    const range = find(name)
    on(range, "input", () => {
      label(name, range.value)
      studio.update({ [name]: Number.parseInt(range.value, 10) })
    })
  }
  for (const input of tokens) {
    on(input, "input", () => {
      studio.setToken(input.dataset.posterToken, input.value)
      tokenLabel(input)
    })
  }

  function refresh() {
    const { state } = studio
    for (const name of ["title", "subtitle"]) {
      const field = find(name)
      if (field && field.value !== state[name]) field.value = state[name]
    }
    label("opacity", state.opacity)
    label("width", state.width)
    if (studio.tokens && studio.tokens !== seededTokens) {
      seededTokens = studio.tokens
      for (const input of tokens) {
        const value = studio.tokens[input.dataset.posterToken]
        if (value) input.value = value
        tokenLabel(input)
      }
    }
  }

  return { refresh }
}
