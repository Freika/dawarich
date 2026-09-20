import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { PointEditHistory } from "./point_edit_history"
import { PointEditHistoryPanel } from "./point_edit_history_panel"

// Connects a MapEditor to its undo/redo history and the panel that shows it.
// The panel is on the map only while editing is on and there is history; a
// closed panel comes back with the next move.
export class EditorHistory {
  constructor(editor, { distanceUnit }) {
    this.editor = editor
    this.closed = false
    this.history = new PointEditHistory({
      move: (pointId, position) => this._move(pointId, position),
      onChange: () => this.sync(),
    })
    this.panel = new PointEditHistoryPanel({
      onUndo: () => this.undo(),
      onRedo: () => this.redo(),
      onTravel: (entry) => this.travelTo(entry),
      onClose: () => this.close(),
      distanceUnit,
    })
  }

  record(move, response) {
    if (this.editor.disposed) return
    this.closed = false
    this.history.record(move, response)
  }

  close() {
    this.closed = true
    this.sync()
  }

  undo() {
    return this._run(() => this.history.undo())
  }

  redo() {
    return this._run(() => this.history.redo())
  }

  travelTo(entry) {
    return this._run(() => this.history.travelTo(entry))
  }

  sync() {
    const { map, editable } = this.editor
    const { entries, undone } = this.history
    const busy =
      this.history.busy ||
      this.editor.mutationState.busy ||
      this.editor.draggedPointId != null
    const shown =
      editable &&
      !this.editor.disposed &&
      !this.closed &&
      entries.length + undone.length > 0
    if (shown && !this.panel.container)
      map.addControl?.(this.panel, "bottom-left")
    else if (!shown && this.panel.container) map.removeControl?.(this.panel)
    this.panel.render({
      entries,
      undone,
      size: this.history.size,
      limit: this.history.limit,
      busy,
      canUndo: this.history.canUndo && !busy,
      canRedo: this.history.canRedo && !busy,
    })
  }

  async _run(step) {
    const editor = this.editor
    if (
      editor.disposed ||
      !editor.editable ||
      editor.mutationState.busy ||
      editor.draggedPointId != null
    )
      return
    const sessionVersion = editor.sessionVersion
    editor.mutationState.busy = true
    this.sync()
    try {
      await step()
    } catch (error) {
      const conflict = error.status === 409
      const point = error.payload?.point
      if (
        conflict &&
        point &&
        sessionVersion === editor.sessionVersion &&
        editor.data &&
        editor._point(point.id)
      )
        editor.applyCanonical(error.payload)
      Toast.error(
        translate(
          conflict
            ? "messages.point_edit_conflict"
            : "messages.failed_to_update_point_position_please_try_again",
        ),
      )
    } finally {
      editor.mutationState.busy = false
      this.sync()
    }
  }

  async _move(pointId, position) {
    const editor = this.editor
    const sessionVersion = editor.sessionVersion
    const response = await editor.apiClient.movePointPosition(pointId, {
      ...position,
      historyScope: editor.historyScope(),
    })
    editor._afterMove(response, sessionVersion, pointId)
    return response
  }
}
