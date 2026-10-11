const MAX_BULK = 500

export function createSelectionActions({
  container,
  document,
  translate,
  selection,
  confirm = (message) => globalThis.confirm(message),
}) {
  const checked = new Set()
  let error = null
  let destroyed = false

  const node = (tag, text, attributes = {}) => {
    const child = document.createElement(tag)
    if (text != null) child.textContent = text
    for (const [name, value] of Object.entries(attributes))
      child.setAttribute(name, value)
    return child
  }

  const button = (text, attributes, onClick) => {
    const child = node("button", text, { type: "button", ...attributes })
    child.addEventListener("click", onClick)
    return child
  }

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

  function visitRow(visit) {
    const id = String(visit.id)
    const row = node("li", null, {
      class: "flex flex-wrap items-center gap-1 min-w-0",
    })
    const box = node("input", null, {
      type: "checkbox",
      "data-visit-select": id,
      "aria-label": visit.name || id,
    })
    box.checked = checked.has(id)
    box.addEventListener("change", () => {
      if (box.checked) checked.add(id)
      else checked.delete(id)
      render()
    })
    row.append(
      box,
      node("span", visit.name || "", {
        class: "min-w-0 [overflow-wrap:anywhere]",
      }),
    )
    if (visit.status === "suggested")
      row.append(
        button(translate("common.confirm"), { "data-visit-confirm": id }, () =>
          visits("confirm", [id], "messages.failed_to_confirm_visits"),
        ),
      )
    row.append(
      button(translate("common.delete"), { "data-visit-delete": id }, () =>
        visits("delete", [id], "messages.failed_to_delete_visit"),
      ),
    )
    return row
  }

  function bulkRow() {
    const ids = [...checked]
    const row = node(
      "div",
      translate("visits.selected", { count: ids.length }),
      {
        class: "flex flex-wrap gap-1",
      },
    )
    const disabled = ids.length > MAX_BULK
    for (const [action, label, failure] of [
      ["merge", "visits.merge", "messages.failed_to_merge_visits"],
      ["confirm", "common.confirm", "messages.failed_to_confirm_visits"],
      ["delete", "common.delete", "messages.failed_to_delete_visit"],
    ]) {
      const child = button(translate(label), { "data-bulk": action }, () =>
        visits(action, ids, failure),
      )
      child.disabled = disabled
      row.append(child)
    }
    return row
  }

  function render() {
    if (destroyed) return
    const { state } = selection
    const anomalies = state.points.filter((point) => point.anomaly === true)
    const children = [
      node("p", translate("selection.points", { count: state.points.length })),
      node("p", translate("selection.visits", { count: state.visits.length })),
    ]
    if (error)
      children.push(node("p", error, { role: "alert", class: "text-error" }))
    if (state.points.length > 0)
      children.push(
        button(translate("common.delete"), { "data-points": "all" }, () =>
          points(
            state.points.map((point) => point.id),
            translate("selection.confirm_delete_points", {
              count: state.points.length,
            }),
          ),
        ),
      )
    if (anomalies.length > 0)
      children.push(
        button(
          translate("selection.delete_anomaly_points", {
            count: anomalies.length,
          }),
          { "data-points": "anomalies" },
          () =>
            points(
              anomalies.map((point) => point.id),
              translate("selection.confirm_delete_anomaly_points", {
                count: anomalies.length,
              }),
            ),
        ),
      )
    if (state.visits.length > 0) {
      const list = node("ul", null, { class: "space-y-1" })
      list.append(...state.visits.map(visitRow))
      children.push(list)
    }
    if (checked.size >= 2) children.push(bulkRow())
    container.replaceChildren(...children)
  }

  function destroy() {
    destroyed = true
    checked.clear()
    container.replaceChildren()
  }

  render()
  return { render, destroy }
}
