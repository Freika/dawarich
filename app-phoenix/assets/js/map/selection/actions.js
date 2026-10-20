import { createVisitCards } from "./visit_card.js"

const MAX_BULK = 500

export function createSelectionActions({
  container,
  document,
  translate,
  selection,
  notify = () => {},
  upgradeUrl = () => "",
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
  let destroyed = false

  async function settle(promise, failure, success, bindings = {}) {
    const result = await promise
    if (destroyed) return result
    notify(result.status === "error" ? "error" : "success", result.status === "error" ? result.failure ?? failure : success, { ...bindings, ...result.bindings, count: result.count ?? bindings.count })
    if (result.status !== "error") checked.clear()
    render()
    return result
  }

  function visits(action, ids, failure) {
    const singular = ids.length === 1
    if (!singular || action === "merge") notify("info", `messages.${{ confirm: "confirming_visits", delete: "deleting_visits", merge: "merging_visits" }[action]}`)
    const success = action === "merge" ? "messages.visits_merged_successfully" : singular ? `messages.visit_${action === "confirm" ? "confirmed" : "deleted"}` : `visits.${action === "confirm" ? "confirmed" : "deleted"}_count`
    return settle(selection.bulkVisits(action, ids), singular && action === "confirm" ? "messages.failed_to_confirm_visit" : failure, success, { count: ids.length })
  }

  function points(ids, prompt, anomaly = false) {
    if (ids.length === 0) {
      notify("error", anomaly ? "messages.no_anomaly_points_in_selection" : "messages.no_points_selected")
      return Promise.resolve(null)
    }
    if (!confirm(prompt)) return Promise.resolve(null)
    notify("info", anomaly ? "messages.deleting_anomaly_points" : "messages.deleting_points")
    return settle(selection.deletePoints(ids).then(result => {
      if (result.status !== "error") return result
      const key = result.error === "forbidden"
        ? `${translate("selection.write_api_requires_pro")} — ${upgradeUrl()}`
        : result.error === "too_many_points_selected"
          ? anomaly ? "selection.too_many_points" : "selection.too_many_selected_points"
          : "selection.delete_points_failed"
      result.failure = key
      result.bindings = { requested: result.requested, limit: result.limit }
      return result
    }), "selection.delete_points_failed", anomaly ? "selection.anomaly_points_deleted" : "selection.points_deleted")
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
      true,
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
        remove: () => visits("delete", ids, "messages.failed_to_delete_visits"),
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
    renderVisits()
  }

  function destroy() {
    destroyed = true
    checked.clear()
    deleteButton?.removeEventListener("click", onDelete)
    anomaliesButton?.removeEventListener("click", onAnomalies)
    visitsBox?.replaceChildren()
  }

  render()
  return { render, destroy }
}
