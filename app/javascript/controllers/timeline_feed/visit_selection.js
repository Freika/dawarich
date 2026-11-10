import { translate } from "i18n"

/**
 * Timeline bulk selection: pick visits, then merge or delete them.
 * Mixed into the controller; `this` is the controller.
 */
export const visitSelection = {
  enterSelection(event) {
    const day = event.currentTarget.closest(".timeline-day")
    if (!day) return

    if (this.selectionMode) {
      const wasSameDay = this.activeDayElement === day
      this.exitSelection()
      if (wasSameDay) return
    }

    this.selectionMode = true
    this.selectedVisitIds.clear()
    this.activeDayElement = day
    day.dataset.selectionMode = "true"

    const bar = this.activeSelectionBar()
    if (bar) bar.hidden = false
    this.syncSelectionUI()
  },

  exitSelection() {
    this.selectionMode = false
    this.selectedVisitIds.clear()

    for (const day of this.element.querySelectorAll(
      '[data-selection-mode="true"]',
    )) {
      day.removeAttribute("data-selection-mode")
    }

    for (const cb of this.rowCheckTargets) {
      cb.checked = false
    }

    const bar = this.activeSelectionBar()
    if (bar) bar.hidden = true

    this.syncSelectionUI()
    this.activeDayElement = null
  },

  toggleVisitId(id) {
    const idStr = String(id)
    if (this.selectedVisitIds.has(idStr)) {
      this.selectedVisitIds.delete(idStr)
    } else {
      this.selectedVisitIds.add(idStr)
    }
    const scope = this.activeDayElement || this.element
    const cb = scope.querySelector(
      `input[type="checkbox"][data-visit-id="${idStr}"]`,
    )
    if (cb) cb.checked = this.selectedVisitIds.has(idStr)
    this.syncSelectionUI()
  },

  rowCheckChanged(event) {
    if (!this.selectionMode) return
    const id = event.target.dataset.visitId
    if (!id) return
    if (event.target.checked) {
      this.selectedVisitIds.add(String(id))
    } else {
      this.selectedVisitIds.delete(String(id))
    }
    this.syncSelectionUI()
  },

  stopPropagation(event) {
    event.stopPropagation()
  },

  activeSelectionBar() {
    const scope = this.activeDayElement
    if (!scope) return null
    return scope.querySelector('[data-timeline-feed-target="selectionBar"]')
  },

  activeSelectionForm() {
    return this.scopedQuery('[data-timeline-feed-target="selectionForm"]')
  },

  activeSelectionCount() {
    return this.scopedQuery('[data-timeline-feed-target="selectionCount"]')
  },

  activeMergeButton() {
    return this.scopedQuery('[data-timeline-feed-target="mergeButton"]')
  },

  activeDeleteForm() {
    return this.scopedQuery('[data-timeline-feed-target="deleteForm"]')
  },

  activeDeleteButton() {
    return this.scopedQuery('[data-timeline-feed-target="deleteButton"]')
  },

  scopedQuery(selector) {
    const scope = this.activeDayElement
    if (!scope) return null
    return scope.querySelector(selector)
  },

  maxBulkVisits() {
    const bar = this.activeSelectionBar()
    const raw = bar?.dataset?.maxBulkVisits
    const n = Number.parseInt(raw, 10)
    return Number.isFinite(n) && n > 0 ? n : 500
  },

  syncSelectionUI() {
    const n = this.selectedVisitIds.size
    const max = this.maxBulkVisits()
    const overCap = n > max
    const countEl = this.activeSelectionCount()
    if (countEl) {
      countEl.textContent = overCap
        ? translate("timeline.selected_with_max", { count: n, max })
        : translate("timeline.selected", { count: n })
    }
    const mergeBtn = this.activeMergeButton()
    if (mergeBtn) {
      mergeBtn.disabled = n < 2 || overCap
      mergeBtn.textContent =
        n >= 2
          ? translate("timeline.merge_count", { count: n })
          : translate("visits.merge")
    }
    for (const [getter, key] of [
      [this.activeDeleteButton.bind(this), "common.delete"],
    ]) {
      const btn = getter()
      if (!btn) continue
      btn.disabled = n < 1 || overCap
      btn.textContent =
        n >= 1
          ? translate("timeline.action_count", {
              action: translate(key),
              count: n,
            })
          : translate(key)
    }
  },

  submitMerge(event) {
    this.submitBulkAction(event, {
      formGetter: this.activeSelectionForm.bind(this),
      buttonGetter: this.activeMergeButton.bind(this),
      minSelected: 2,
    })
  },

  submitBulkDelete(event) {
    const n = this.selectedVisitIds.size
    if (n < 1) {
      event.preventDefault()
      return
    }
    const noun = n === 1 ? "visit" : "visits"
    const message = `Delete ${n} ${noun}? Your location points stay — only the visit grouping is removed.`
    if (!window.confirm(message)) {
      event.preventDefault()
      return
    }
    this.submitBulkAction(event, {
      formGetter: this.activeDeleteForm.bind(this),
      buttonGetter: this.activeDeleteButton.bind(this),
      minSelected: 1,
    })
  },

  submitBulkAction(event, { formGetter, buttonGetter, minSelected }) {
    const form = formGetter()
    if (!form || form !== event.currentTarget) {
      event.preventDefault()
      return
    }
    if (this.selectedVisitIds.size < minSelected) {
      event.preventDefault()
      return
    }

    for (const old of form.querySelectorAll('input[name="visit_ids[]"]')) {
      old.remove()
    }
    for (const id of this.selectedVisitIds) {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "visit_ids[]"
      input.value = id
      form.appendChild(input)
    }

    const btn = buttonGetter()
    if (btn) btn.disabled = true

    const onEnd = (e) => {
      if (e.target !== form) return
      document.removeEventListener("turbo:submit-end", onEnd)
      if (e.detail?.success) {
        this.exitSelection()
      } else {
        this.syncSelectionUI()
      }
    }
    document.addEventListener("turbo:submit-end", onEnd)
  },
}
