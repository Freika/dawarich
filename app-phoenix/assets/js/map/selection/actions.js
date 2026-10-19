import { createVisitCards } from "./visit_card.js"

const MAX_BULK = 500

export function createSelectionActions({
  container,
  document,
  translate,
  selection,
  confirm = (message) => globalThis.confirm(message),
}) {
  const checked = new Set()
  const cards = createVisitCards({ document, translate })
  const find = (selector) => container.querySelector?.(selector) ?? null
  const deleteButton = find("[data-map-delete-points]")
  const deleteText = find("[data-map-delete-points-text]")
  const anomaliesButton = find("[data-map-delete-anomalies]")
  const anomaliesText = find("[data-map-delete-anomalies-text]")
  const visitsBox = find("[data-map-selected-visits]")
  let error = null
  let alert = null
  let destroyed = false

  async function settle(promise, failure) {
    const result = await promise
    if (destroyed) return result
    error = result.status === "error" ? translate(failure) : null
    if (result.status !== "error") checked.clear()
    render()
    return result
  }

  function visits(action, ids, failure) {
    return settle(selection.bulkVisits(action, ids), failure)
  }

  function points(ids, prompt) {
    if (ids.length === 0 || !confirm(prompt)) return Promise.resolve(null)
    return settle(selection.deletePoints(ids), "selection.delete_points_failed")
  }

  const anomalies = () =>
    selection.state.points.filter((point) => point.anomaly === true)

  const onDelete = () =>
    points(
      selection.state.points.map((point) => point.id),
      translate("selection.confirm_delete_points", {
        count: selection.state.points.length,
      }),
    )
  const onAnomalies = () => {
    const rows = anomalies()
    return points(
      rows.map((point) => point.id),
      translate("selection.confirm_delete_anomaly_points", {
        count: rows.length,
      }),
    )
  }
  deleteButton?.addEventListener("click", onDelete)
  anomaliesButton?.addEventListener("click", onAnomalies)

  function visitCard(visit) {
    const id = String(visit.id)
    return cards.card(visit, {
      selected: checked.has(id),
      onSelect: (on) => {
        if (on) checked.add(id)
        else checked.delete(id)
        render()
      },
      onConfirm: () =>
        visits("confirm", [id], "messages.failed_to_confirm_visits"),
      onDelete: () => visits("delete", [id], "messages.failed_to_delete_visit"),
    })
  }

  function renderVisits() {
    if (!visitsBox) return
    const rows = selection.state.visits
    if (rows.length === 0) {
      visitsBox.replaceChildren()
      visitsBox.classList.add("hidden")
      return
    }
    const list = rows.map(visitCard)
    if (checked.size >= 2) {
      const ids = [...checked]
      const last = list.findLast((card) =>
        checked.has(card.getAttribute("data-visit-id")),
      )
      const bulk = cards.bulk(ids.length, {
        disabled: ids.length > MAX_BULK,
        merge: () => visits("merge", ids, "messages.failed_to_merge_visits"),
        confirm: () =>
          visits("confirm", ids, "messages.failed_to_confirm_visits"),
        remove: () => visits("delete", ids, "messages.failed_to_delete_visit"),
      })
      list.splice(list.indexOf(last) + 1, 0, bulk)
    }
    visitsBox.replaceChildren(cards.list(rows.length, list))
    visitsBox.classList.remove("hidden")
  }

  function render() {
    if (destroyed) return
    const { state } = selection
    if (deleteText)
      deleteText.textContent = translate("selection.delete_points", {
        count: state.points.length,
      })
    const noisy = anomalies()
    anomaliesButton?.classList.toggle("hidden", noisy.length === 0)
    if (anomaliesText)
      anomaliesText.textContent = translate("selection.delete_anomaly_points", {
        count: noisy.length,
      })
    alert?.remove()
    alert = null
    if (error) {
      alert = document.createElement("p")
      alert.className = "text-error text-sm"
      alert.setAttribute("role", "alert")
      alert.textContent = error
      container.prepend?.(alert)
    }
    renderVisits()
  }

  function destroy() {
    destroyed = true
    checked.clear()
    deleteButton?.removeEventListener("click", onDelete)
    anomaliesButton?.removeEventListener("click", onAnomalies)
    alert?.remove()
    visitsBox?.replaceChildren()
  }

  render()
  return { render, destroy }
}
