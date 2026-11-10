import { translate } from "i18n"

/**
 * Timeline visit filters: status checkboxes, search and tag chips.
 * Mixed into the controller; `this` is the controller.
 */
export const visitFilters = {
  // ---------- Filters + Search ----------
  filterChanged() {
    if (this.selectionMode) this.exitSelection()
    this.applyVisibility()
    document.dispatchEvent(
      new CustomEvent("timeline-feed:filter-changed", {
        detail: this.readFilterDetail(),
      }),
    )
  },

  // Stimulus action wired via `data-action="input->timeline-feed#search"`.
  search() {
    this.applyVisibility()
  },

  // Stimulus action on tag chips. Toggles `--active` class + aria-pressed and
  // re-applies row visibility. Multiple active chips AND together.
  toggleTag(event) {
    const btn = event.currentTarget
    const isActive = btn.classList.toggle("tag-chip--active")
    btn.setAttribute("aria-pressed", isActive ? "true" : "false")
    this.applyVisibility()
  },

  // Single source of truth — walks the rendered visit rows and toggles the
  // hidden class based on filter checkboxes, search query, and active tag chips.
  // Keeping them unified prevents the three from drifting out of sync.
  //
  // Tag semantics are OR (union) — selecting "#home" + "#gym" shows visits
  // tagged with either. AND would require visits carrying BOTH tags, which
  // doesn't match how users read "show me home AND gym visits".
  applyVisibility() {
    if (!this.hasVisitListFrameTarget) return

    const filter = this.readFilterDetail()
    const query = this.readSearchQuery()
    const activeTags = this.readActiveTags()

    const filtersActive =
      query.length > 0 ||
      activeTags.length > 0 ||
      Object.values(filter).some((v) => v === false)

    for (const day of this.visitListFrameTarget.querySelectorAll(
      ".timeline-day",
    )) {
      const rows = day.querySelectorAll(".visit-row[data-status]")
      let visibleCount = 0
      // Searching includes the normally collapsed low-confidence stops.
      day.classList.toggle("timeline-day--filtering", filtersActive)
      for (const row of rows) {
        const tokens = row.dataset.searchTokens || ""
        const statusOk = filter[row.dataset.status] !== false
        const searchOk = !query || tokens.includes(query)
        const tagsOk =
          activeTags.length === 0 || activeTags.some((t) => tokens.includes(t))
        const hidden = !(statusOk && searchOk && tagsOk)
        row.classList.toggle("visit-row--hidden", hidden)
        const collapsed =
          !filtersActive &&
          row.classList.contains("visit-row--lowconf") &&
          !day.classList.contains("timeline-day--show-lowconf")
        if (!hidden && !collapsed) visibleCount += 1
      }
      const count = day.querySelector("[data-timeline-visit-count]")
      if (count) {
        count.textContent = translate(
          filtersActive || visibleCount !== rows.length
            ? "ux_p3.timeline.filtered_count"
            : "ux_p3.timeline.visit_count",
          { count: visibleCount, total: rows.length },
        )
      }
      day
        .querySelector("[data-timeline-filter-scope]")
        ?.classList.toggle("hidden", !filtersActive)
      day
        .querySelector('[data-timeline-feed-target="emptyFiltered"]')
        ?.classList.toggle(
          "hidden",
          !(rows.length > 0 && visibleCount === 0 && filtersActive),
        )
    }
  },

  // Wired from the empty-filtered helper's "Clear search & filters" button.
  clearVisitFilters() {
    if (this.hasSearchInputTarget) {
      this.searchInputTarget.value = ""
    }
    const checkboxes = this.element.querySelectorAll(
      'input[type="checkbox"][data-status]',
    )
    for (const cb of checkboxes) {
      if (!cb.checked) cb.checked = true
    }
    const activeTagChips = this.element.querySelectorAll(
      ".tag-chip--toggle.tag-chip--active",
    )
    for (const chip of activeTagChips) {
      chip.classList.remove("tag-chip--active")
    }
    this.applyVisibility()
  },

  // Built from whatever status checkboxes exist in the DOM. With none
  // rendered (stateless visits), the empty detail filters nothing.
  readFilterDetail() {
    const detail = {}
    const checkboxes = this.element.querySelectorAll(
      'input[type="checkbox"][data-status]',
    )
    for (const cb of checkboxes) {
      detail[cb.dataset.status] = cb.checked
    }
    return detail
  },

  readSearchQuery() {
    if (!this.hasSearchInputTarget) return ""
    return (this.searchInputTarget.value || "").trim().toLowerCase()
  },

  readActiveTags() {
    return Array.from(
      this.element.querySelectorAll(".tag-chip--toggle.tag-chip--active"),
    ).map((b) => b.dataset.tagName || "")
  },
}
