export const DIRECT_DRAG_MIN_ZOOM = 14
const MOUSE_DRAG_THRESHOLD_PX = 4
const TOUCH_SLOP_PX = 10
const TOUCH_HIT_RADIUS_PX = 12
const LONG_PRESS_MS = 450

const distance = (a, b) => Math.hypot(a.x - b.x, a.y - b.y)

function hitBox(point, radius) {
  if (!radius) return point
  return [
    [point.x - radius, point.y - radius],
    [point.x + radius, point.y + radius],
  ]
}

// Recognises point drags that start on the map itself: a mouse press on a
// tile point that moves past a small threshold, or a long press on a tile or
// open-editor point. Points already open in the editor keep the editor's own
// mouse handling; short presses fall through to the regular click.
export class PointDragGesture {
  constructor(
    map,
    { isEnabled, getEditor, isSinglePoint, longPressMs = LONG_PRESS_MS },
  ) {
    this.map = map
    this.isEnabled = isEnabled
    this.getEditor = getEditor
    this.isSinglePoint = isSinglePoint
    this.longPressMs = longPressMs
    this.press = null
    this._onMouseDown = this.onMouseDown.bind(this)
    this._onMouseMove = this.onMouseMove.bind(this)
    this._onMouseUp = this.onMouseUp.bind(this)
    this._onTouchStart = this.onTouchStart.bind(this)
    this._onTouchMove = this.onTouchMove.bind(this)
    this._onTouchEnd = this.onTouchEnd.bind(this)
    this._onTouchCancel = this.onTouchCancel.bind(this)
  }

  attach() {
    this.map.on("mousedown", this._onMouseDown)
    this.map.on("touchstart", this._onTouchStart)
  }

  detach() {
    this.cancel()
    this.map.off("mousedown", this._onMouseDown)
    this.map.off("touchstart", this._onTouchStart)
  }

  cancel() {
    const press = this.press
    if (!press) return
    this._unlisten()
    clearTimeout(press.timer)
    if (press.dragging) press.begun?.then((editor) => editor?.cancelDrag())
    this._clear(press)
  }

  canDrag(properties) {
    return (
      this.isEnabled() &&
      this.map.getZoom() >= DIRECT_DRAG_MIN_ZOOM &&
      this.isSinglePoint(properties)
    )
  }

  onMouseDown(event) {
    if (this.press || (event.originalEvent?.button ?? 0) !== 0) return
    const feature = this._tileFeatureAt(event.point)
    if (!feature) return

    event.preventDefault()
    this.press = { feature, start: event.point, latest: event.lngLat }
    this.map.on("mousemove", this._onMouseMove)
    this.map.once("mouseup", this._onMouseUp)
  }

  onMouseMove(event) {
    const press = this.press
    if (!press) return
    press.latest = event.lngLat
    if (!press.dragging) {
      if (distance(event.point, press.start) < MOUSE_DRAG_THRESHOLD_PX) return
      press.dragging = true
      press.begun = this._begin(press, (editor) =>
        editor.beginTileDrag(press.feature),
      )
      return
    }
    press.editor?.dragTo(event.lngLat.lng, event.lngLat.lat)
  }

  onMouseUp(event) {
    this._unlisten()
    const press = this.press
    if (!press) return
    if (event?.lngLat) press.latest = event.lngLat
    return this._release(press)
  }

  onTouchStart(event) {
    if (this.press || event.originalEvent?.touches?.length !== 1) return
    if (!this.isEnabled()) return
    const overlay = this._overlayFeatureAt(event.point, TOUCH_HIT_RADIUS_PX)
    const feature =
      overlay || this._tileFeatureAt(event.point, TOUCH_HIT_RADIUS_PX)
    if (!feature) return

    const press = {
      feature,
      overlay: Boolean(overlay),
      touch: true,
      start: event.point,
      latest: event.lngLat,
    }
    press.timer = setTimeout(
      () => this._startTouchDrag(press),
      this.longPressMs,
    )
    this.press = press
    this.map.on("touchmove", this._onTouchMove)
    this.map.once("touchend", this._onTouchEnd)
    this.map.once("touchcancel", this._onTouchCancel)
  }

  onTouchMove(event) {
    const press = this.press
    if (!press?.touch) return
    if (!press.dragging) {
      if (distance(event.point, press.start) > TOUCH_SLOP_PX) this.cancel()
      return
    }
    event.preventDefault()
    press.latest = event.lngLat
    press.editor?.dragTo(event.lngLat.lng, event.lngLat.lat)
  }

  onTouchEnd() {
    this._unlisten()
    const press = this.press
    if (!press) return
    clearTimeout(press.timer)
    return this._release(press)
  }

  onTouchCancel() {
    this.cancel()
  }

  _startTouchDrag(press) {
    if (this.press !== press) return
    press.dragging = true
    press.dragPanWasEnabled = this.map.dragPan?.isEnabled?.() === true
    this.map.dragPan?.disable?.()
    press.begun = this._begin(press, (editor) =>
      press.overlay
        ? editor.startDrag(Number(press.feature.properties.id))
        : editor.beginTileDrag(press.feature),
    )
  }

  async _begin(press, start) {
    const editor = await this.getEditor()
    if (this.press !== press || !start(editor)) return null
    press.editor = editor
    editor.dragTo(press.latest.lng, press.latest.lat)
    return editor
  }

  async _release(press) {
    if (!press.dragging) {
      this._clear(press)
      return
    }
    const editor = await press.begun
    this._clear(press)
    if (!editor) return
    editor.dragTo(press.latest.lng, press.latest.lat)
    await editor.endDrag(press.latest)
  }

  _clear(press) {
    if (this.press === press) this.press = null
    if (press.dragPanWasEnabled) this.map.dragPan.enable()
    press.dragPanWasEnabled = false
  }

  _unlisten() {
    this.map.off("mousemove", this._onMouseMove)
    this.map.off("mouseup", this._onMouseUp)
    this.map.off("touchmove", this._onTouchMove)
    this.map.off("touchend", this._onTouchEnd)
    this.map.off("touchcancel", this._onTouchCancel)
  }

  _tileFeatureAt(point, radius = 0) {
    if (this.map.getZoom() < DIRECT_DRAG_MIN_ZOOM || !this.isEnabled())
      return null
    if (!this.map.getLayer("points-mvt")) return null
    if (this._overlayFeatureAt(point, radius)) return null
    const [feature] = this.map.queryRenderedFeatures(hitBox(point, radius), {
      layers: ["points-mvt"],
    })
    return feature && this.isSinglePoint(feature.properties) ? feature : null
  }

  _overlayFeatureAt(point, radius = 0) {
    if (!this.map.getLayer("track-points")) return null
    const [feature] = this.map.queryRenderedFeatures(hitBox(point, radius), {
      layers: ["track-points"],
    })
    return feature || null
  }
}
