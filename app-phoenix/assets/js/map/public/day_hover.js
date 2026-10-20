export function syncPublicDays(root, color = () => null, selected = null) {
  const owned = (el) => el.closest?.("[data-native-map-root]") === root
  for (const dot of root?.querySelectorAll?.("[data-day-dot]") ?? [])
    if (owned(dot)) dot.style.backgroundColor = color(dot.dataset.dayDot) || ""
  for (const row of root?.querySelectorAll?.("[data-public-day]") ?? [])
    if (owned(row))
      for (const name of ["ring-2", "ring-primary"])
        row.classList.toggle(name, row.dataset.publicDay === selected)
}

export function bindPublicDays(
  root,
  {
    preview,
    selected = () => null,
    allowed = () => true,
    hasDay = () => true,
    sync = () => {},
  },
) {
  if (!root?.addEventListener) return () => {}
  let alive = true
  const rowFor = (target) => {
    const row = target?.closest?.("[data-public-day]")
    return row?.closest?.("[data-native-map-root]") === root &&
      /^\d{4}-\d{2}-\d{2}$/.test(row.dataset.publicDay)
      ? row
      : null
  }
  const change = (event) => {
    if (!alive || !allowed()) return
    const row = rowFor(event.target)
    if (
      !row ||
      rowFor(event.relatedTarget) === row ||
      !hasDay(row.dataset.publicDay)
    )
      return
    preview(
      ["mouseover", "focusin"].includes(event.type)
        ? row.dataset.publicDay
        : selected(),
    )
  }
  const choose = (event) => {
    if (!alive || !allowed()) return
    const row = rowFor(event.target)
    if (
      !row ||
      (event.type === "keydown" && !["Enter", " "].includes(event.key))
    )
      return
    if (!hasDay(row.dataset.publicDay)) event.stopPropagation()
    if (
      event.type === "keydown" &&
      event.key === " " &&
      row.tagName !== "DETAILS"
    ) {
      event.preventDefault()
      if (hasDay(row.dataset.publicDay)) row.click()
    }
  }
  const events = ["mouseover", "mouseout", "focusin", "focusout"]
  for (const event of events) root.addEventListener(event, change)
  for (const event of ["click", "keydown"]) root.addEventListener(event, choose)
  const target = root.querySelector?.("[data-public-days]")
  const Observer = root.ownerDocument?.defaultView?.MutationObserver
  const observer =
    target &&
    Observer &&
    new Observer(() => {
      if (alive && allowed()) sync()
    })
  observer?.observe(target, { childList: true, subtree: true })
  return () => {
    alive = false
    observer?.disconnect()
    for (const event of events) root.removeEventListener(event, change)
    for (const event of ["click", "keydown"])
      root.removeEventListener(event, choose)
  }
}
