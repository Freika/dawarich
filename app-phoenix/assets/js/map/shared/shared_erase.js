export function clearGalleries(el) {
  for (const details of el.querySelectorAll("details[data-public-gallery]"))
    details.publicPhotos = []
  for (const image of el.querySelectorAll("[data-public-gallery] img")) {
    image.removeAttribute?.("src")
    image.removeAttribute?.("srcset")
  }
  for (const content of el.querySelectorAll("[data-public-gallery-content]"))
    content.replaceChildren()
}

export function eraseMapCanvas(el, kind) {
  const canvas = el.querySelector(`[data-${kind}-canvas]`)
  if (canvas) {
    canvas.hidden = true
    canvas.replaceChildren()
  }
  const empty = el.querySelector(`[data-${kind}-empty]`)
  if (empty) empty.hidden = false
}

export function erasePublic(el, hidden = true) {
  clearGalleries(el)
  eraseMapCanvas(el, "public")
  const status = el.querySelector("[data-public-status]")
  if (status) status.hidden = false
  const seen = el.querySelector("[data-public-last-seen]")
  if (seen) seen.textContent = ""
  const content = el.querySelector("[data-public-content]")
  if (content) content.hidden = hidden
}

export function eraseFamily(el) {
  eraseMapCanvas(el, "family")
  for (const row of el
    .closest("#family-shell")
    ?.querySelectorAll(
      "[data-family-member-id], [data-family-last-seen], button[phx-click=family_focus]",
    ) || [])
    row.hidden = true
}
