export function syncSidebarLayout(panel, container, initial = false) {
  if (!panel || !container) return

  const open = panel.classList.contains("open")
  container.classList.toggle("panel-open", open)
  container.classList.toggle(
    "panel-timeline-expanded",
    open && panel.classList.contains("timeline-expanded"),
  )

  if (initial) {
    container.getBoundingClientRect()
    container.parentElement.dataset.sidebarLayoutReady = "true"
  }
}
