import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"
import Flash from "./flash_controller"
import { MapPreview } from "./video_export_map_preview"
import {
  LANDSCAPE_LAYOUTS,
  PORTRAIT_LAYOUTS,
  PRESETS,
  SCREEN_PRESETS,
} from "./video_export_presets"

export default class extends Controller {
  static targets = [
    "modal",
    "form",
    "trackIdInput",
    "startAtInput",
    "endAtInput",
    "orientation",
    "overlayLayout",
    "targetDuration",
    "mapStyle",
    "mapBehavior",
    "routeColor",
    "routeWidth",
    "markerStyle",
    "markerColor",
    "markerColorHexLabel",
    "trackName",
    "fitFullRoute",
    "colorHexLabel",
    "overlayTime",
    "overlaySpeed",
    "overlayDistance",
    "overlayTrackName",
    "submitButton",
    "submitText",
    "submitLoading",
    "submitIcon",
    "screenPresetsContainer",
    "screenPresetInput",
    "mapPreview",
    "mapPreviewWrapper",
  ]

  static values = { apiKey: String }

  connect() {
    this.channel = consumer.subscriptions.create(
      { channel: "VideoExportsChannel" },
      { received: (data) => this._handleStatusUpdate(data) },
    )

    this._boundOpen = (e) => this.open(e)
    document.addEventListener("videoExport:open", this._boundOpen)

    this._renderScreenPresetRows()
  }

  disconnect() {
    if (this.channel) {
      this.channel.unsubscribe()
      this.channel = null
    }

    document.removeEventListener("videoExport:open", this._boundOpen)
  }

  open(event) {
    const { trackId, startAt, endAt } = event.detail || {}

    this.trackIdInputTarget.value = trackId || ""
    this.startAtInputTarget.value = startAt || ""
    this.endAtInputTarget.value = endAt || ""

    this.modalTarget.classList.add("modal-open")
    this._showMapPreview(trackId)
  }

  close() {
    this.modalTarget.classList.remove("modal-open")
    this._resetForm()
  }

  async submit(event) {
    event.preventDefault()

    this._setLoading(true)

    const config = {
      orientation: this.orientationTarget.value,
      overlay_layout: this.overlayLayoutTarget.value,
      map_style: this.mapStyleTarget.value,
      target_duration: parseInt(this.targetDurationTarget.value, 10),
      map_behavior: this.mapBehaviorTarget.value,
      fit_full_route: this.fitFullRouteTarget.checked,
      route_color: this.routeColorTarget.value,
      route_width: parseInt(this.routeWidthTarget.value, 10),
      marker_style: this.markerStyleTarget.value,
      marker_color: this.markerColorTarget.value,
      track_name: this.trackNameTarget.value || "",
      overlays: {
        time: this.overlayTimeTarget.checked,
        speed: this.overlaySpeedTarget.checked,
        distance: this.overlayDistanceTarget.checked,
        track_name: this.overlayTrackNameTarget.checked,
      },
    }

    const screenPreset = this.screenPresetInputTarget.value
    if (screenPreset) {
      config.screen_preset = screenPreset
    }

    const payload = {
      track_id: this.trackIdInputTarget.value
        ? parseInt(this.trackIdInputTarget.value, 10)
        : null,
      start_at: this.startAtInputTarget.value,
      end_at: this.endAtInputTarget.value,
      config,
    }

    try {
      const response = await fetch("/api/v1/video_exports", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${this.apiKeyValue}`,
        },
        body: JSON.stringify(payload),
      })

      if (response.ok) {
        Flash.show(
          "success",
          "Video export started. You'll be notified when it's ready.",
        )
        this.close()
      } else {
        const data = await response.json()
        Flash.show(
          "error",
          data.errors?.join(", ") || "Failed to start video export",
        )
      }
    } catch (error) {
      Flash.show("error", `Error: ${error.message}`)
    } finally {
      this._setLoading(false)
    }
  }

  applyPreset(event) {
    const presetName = event.currentTarget.dataset.preset
    const preset = PRESETS[presetName]
    if (!preset) return

    // Update active preset button styling
    for (const btn of this.element.querySelectorAll("[data-preset]")) {
      btn.classList.remove("btn-active", "btn-primary")
      btn.classList.add("btn-outline")
    }
    event.currentTarget.classList.remove("btn-outline")
    event.currentTarget.classList.add("btn-active", "btn-primary")

    this.orientationTarget.value = preset.orientation
    this._updateLayoutOptions(preset.orientation)
    this.overlayLayoutTarget.value = preset.overlay_layout
    this.mapStyleTarget.value = preset.map_style
    this.targetDurationTarget.value = preset.target_duration
    this.mapBehaviorTarget.value = preset.map_behavior
    this.fitFullRouteTarget.checked = preset.fit_full_route
    this.routeColorTarget.value = preset.route_color
    this.colorHexLabelTarget.textContent = preset.route_color
    this.routeWidthTarget.value = preset.route_width
    this.markerStyleTarget.value = preset.marker_style
    this.markerColorTarget.value = preset.marker_color
    this.markerColorHexLabelTarget.textContent = preset.marker_color
    this.overlayTimeTarget.checked = preset.overlay_time
    this.overlaySpeedTarget.checked = preset.overlay_speed
    this.overlayDistanceTarget.checked = preset.overlay_distance
    this.overlayTrackNameTarget.checked = preset.overlay_track_name

    // Expand matching screen preset row, collapse others
    this._expandScreenPresetRow(presetName)

    // Update map preview with new preset values
    if (this.preview) {
      this.preview.updateOrientation(preset.orientation)
      this.preview.applyAll({
        style: preset.map_style,
        routeColor: preset.route_color,
        routeWidth: Number.parseInt(preset.route_width, 10),
        markerColor: preset.marker_color,
        markerStyle: preset.marker_style,
        layout: preset.overlay_layout,
        duration: Number.parseInt(preset.target_duration, 10),
        mapBehavior: preset.map_behavior,
        fitFullRoute: preset.fit_full_route,
        overlays: {
          time: preset.overlay_time,
          speed: preset.overlay_speed,
          distance: preset.overlay_distance,
          track_name: preset.overlay_track_name,
        },
      })
    }
  }

  selectScreenPreset(event) {
    const card = event.currentTarget
    const key = card.dataset.screenPresetKey

    // Remove selection from all cards
    for (const el of this.screenPresetsContainerTarget.querySelectorAll(
      "[data-screen-preset-key]",
    )) {
      el.classList.remove("border-primary", "ring-2", "ring-primary/30")
      el.classList.add("border-base-300")
    }

    // Highlight selected card
    card.classList.remove("border-base-300")
    card.classList.add("border-primary", "ring-2", "ring-primary/30")

    this.screenPresetInputTarget.value = key
  }

  updateOrientation() {
    this._updateLayoutOptions(this.orientationTarget.value)
  }

  updateColorLabel() {
    this.colorHexLabelTarget.textContent = this.routeColorTarget.value
  }

  updateMarkerColorLabel() {
    this.markerColorHexLabelTarget.textContent = this.markerColorTarget.value
  }

  updateMapPreview(event) {
    if (!this.preview) return

    const name = event.target.name
    const value = event.target.value

    switch (name) {
      case "map_style":
        this.preview.updateStyle(value)
        break
      case "route_color":
        this.preview.updateRouteColor(value)
        break
      case "route_width":
        this.preview.updateRouteWidth(Number.parseInt(value, 10))
        break
      case "marker_color":
        this.preview.updateMarkerColor(value)
        break
      case "orientation":
        this.preview.updateOrientation(value)
        break
      case "overlay_layout":
        this.preview.updateLayout(value)
        break
      case "marker_style":
        this.preview.updateMarkerStyle(value)
        break
    }
  }

  updateOverlays() {
    if (!this.preview) return
    this.preview.updateOverlayVisibility({
      time: this.overlayTimeTarget.checked,
      speed: this.overlaySpeedTarget.checked,
      distance: this.overlayDistanceTarget.checked,
      track_name: this.overlayTrackNameTarget.checked,
    })
  }

  updateTrackNamePreview() {
    if (!this.preview) return
    this.preview.updateTrackName(this.trackNameTarget.value)
  }

  // Private methods

  _showMapPreview(trackId) {
    if (this.preview) {
      this.preview.destroy()
      this.preview = null
    }

    this.preview = new MapPreview(
      this.mapPreviewTarget,
      this.mapPreviewWrapperTarget,
      this.apiKeyValue,
    )
    this.preview.show(trackId || null, {
      style: this.mapStyleTarget.value,
      routeColor: this.routeColorTarget.value,
      routeWidth: Number.parseInt(this.routeWidthTarget.value, 10),
      markerColor: this.markerColorTarget.value,
      markerStyle: this.markerStyleTarget.value,
      layout: this.overlayLayoutTarget.value,
      duration: Number.parseInt(this.targetDurationTarget.value, 10),
      mapBehavior: this.mapBehaviorTarget.value,
      fitFullRoute: this.fitFullRouteTarget.checked,
      trackName: this.trackNameTarget.value,
      overlays: {
        time: this.overlayTimeTarget.checked,
        speed: this.overlaySpeedTarget.checked,
        distance: this.overlayDistanceTarget.checked,
        track_name: this.overlayTrackNameTarget.checked,
      },
    })
  }

  _renderScreenPresetRows() {
    const container = this.screenPresetsContainerTarget
    container.innerHTML = ""

    for (const [category, { portrait, presets }] of Object.entries(
      SCREEN_PRESETS,
    )) {
      const row = document.createElement("div")
      row.dataset.screenPresetCategory = category
      row.className = "overflow-hidden transition-all duration-300 ease-in-out"
      row.style.maxHeight = "0"
      row.style.opacity = "0"

      const inner = document.createElement("div")
      inner.className = "grid grid-cols-5 gap-2 py-2"

      const aspectClass = portrait ? "aspect-[9/16]" : "aspect-video"

      for (const preset of presets) {
        const card = document.createElement("div")
        card.dataset.screenPresetKey = preset.key
        card.dataset.action = "click->video-export-modal#selectScreenPreset"
        card.className =
          "cursor-pointer rounded-lg border-2 border-base-300 p-1 text-center transition-colors hover:border-primary/50"

        card.innerHTML = `
          <img src="/video_presets/${preset.key}.png"
               alt="${preset.label}"
               class="w-full rounded ${aspectClass} object-cover bg-base-300"
               loading="lazy"
               onerror="this.style.display='none'">
          <div class="text-xs mt-1 text-base-content/70 truncate">${preset.label}</div>
        `

        inner.appendChild(card)
      }

      row.appendChild(inner)
      container.appendChild(row)
    }
  }

  _expandScreenPresetRow(category) {
    const rows = this.screenPresetsContainerTarget.querySelectorAll(
      "[data-screen-preset-category]",
    )

    for (const row of rows) {
      if (row.dataset.screenPresetCategory === category) {
        // Temporarily remove overflow and max-height to measure true content height
        row.style.transition = "none"
        row.style.maxHeight = "none"
        row.style.overflow = "visible"
        const fullHeight = row.scrollHeight
        row.style.maxHeight = "0"
        row.style.overflow = "hidden"
        // Force reflow before re-enabling transition
        row.offsetHeight // eslint-disable-line no-unused-expressions
        row.style.transition = ""
        row.style.maxHeight = `${fullHeight}px`
        row.style.opacity = "1"

        // Auto-select the first preset in the expanded row
        const firstCard = row.querySelector("[data-screen-preset-key]")
        if (firstCard && !this.screenPresetInputTarget.value) {
          this.selectScreenPreset({ currentTarget: firstCard })
        }
      } else {
        row.style.maxHeight = "0"
        row.style.opacity = "0"
      }
    }
  }

  _updateLayoutOptions(orientation) {
    const layouts =
      orientation === "portrait" ? PORTRAIT_LAYOUTS : LANDSCAPE_LAYOUTS
    this.overlayLayoutTarget.innerHTML = layouts
      .map((l) => `<option value="${l.value}">${l.label}</option>`)
      .join("")
  }

  _setLoading(loading) {
    this.submitButtonTarget.disabled = loading

    if (loading) {
      this.submitTextTarget.textContent = "Submitting..."
      this.submitIconTarget.classList.add("hidden")
      this.submitLoadingTarget.classList.remove("hidden")
    } else {
      this.submitTextTarget.textContent = "Generate Video"
      this.submitIconTarget.classList.remove("hidden")
      this.submitLoadingTarget.classList.add("hidden")
    }
  }

  _resetForm() {
    if (this.preview) {
      this.preview.destroy()
      this.preview = null
    }

    this.formTarget.reset()

    // Reset preset button styling
    for (const btn of this.element.querySelectorAll("[data-preset]")) {
      btn.classList.remove("btn-active", "btn-primary")
      btn.classList.add("btn-outline")
    }

    // Reset layout options to landscape defaults
    this._updateLayoutOptions("landscape")

    // Reset color hex labels
    this.colorHexLabelTarget.textContent = "#3b82f6"
    this.markerColorHexLabelTarget.textContent = "#ef4444"

    // Reset screen preset selection
    this.screenPresetInputTarget.value = ""
    for (const el of this.screenPresetsContainerTarget.querySelectorAll(
      "[data-screen-preset-key]",
    )) {
      el.classList.remove("border-primary", "ring-2", "ring-primary/30")
      el.classList.add("border-base-300")
    }

    // Collapse all screen preset rows
    for (const row of this.screenPresetsContainerTarget.querySelectorAll(
      "[data-screen-preset-category]",
    )) {
      row.style.maxHeight = "0"
      row.style.opacity = "0"
    }
  }

  _handleStatusUpdate(data) {
    const name = data.name || "Unknown"
    if (data.status === "completed") {
      Flash.show(
        "success",
        `Video "${name}" is ready! Visit Video Exports to download.`,
      )
    } else if (data.status === "failed") {
      Flash.show(
        "error",
        `Video "${name}" failed: ${data.error_message || "Unknown error"}`,
      )
    }
  }
}
