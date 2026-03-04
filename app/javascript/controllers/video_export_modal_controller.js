import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"
import Flash from "./flash_controller"

const LANDSCAPE_LAYOUTS = [
  { value: "bottom_bar", label: "Bottom Bar" },
  { value: "corner_hud", label: "Corner HUD" },
  { value: "left_rail", label: "Left Rail" },
  { value: "bottom_left", label: "Bottom-Left" },
  { value: "cinematic_strip", label: "Cinematic Strip" },
]

const PORTRAIT_LAYOUTS = [
  { value: "bottom_stack", label: "Bottom Stack" },
  { value: "bottom_row_card", label: "Bottom Row" },
  { value: "split_bands", label: "Split Bands" },
  { value: "right_rail", label: "Right Rail" },
  { value: "floating_pills", label: "Floating Pills" },
]

const PRESETS = {
  sporty: {
    orientation: "landscape",
    overlay_layout: "bottom_bar",
    map_style: "dark",
    target_duration: "30",
    map_behavior: "follow_direction",
    fit_full_route: false,
    route_color: "#3b82f6",
    route_width: "4",
    marker_style: "dot",
    marker_color: "#ef4444",
    overlay_time: true,
    overlay_speed: true,
    overlay_distance: true,
    overlay_track_name: true,
  },
  minimal: {
    orientation: "landscape",
    overlay_layout: "cinematic_strip",
    map_style: "white",
    target_duration: "30",
    map_behavior: "north_up",
    fit_full_route: false,
    route_color: "#1a1a2e",
    route_width: "4",
    marker_style: "dot",
    marker_color: "#374151",
    overlay_time: false,
    overlay_speed: false,
    overlay_distance: true,
    overlay_track_name: false,
  },
  social: {
    orientation: "portrait",
    overlay_layout: "bottom_row_card",
    map_style: "dark",
    target_duration: "15",
    map_behavior: "follow_direction",
    fit_full_route: false,
    route_color: "#3b82f6",
    route_width: "4",
    marker_style: "dot",
    marker_color: "#ef4444",
    overlay_time: true,
    overlay_speed: true,
    overlay_distance: true,
    overlay_track_name: true,
  },
  cinematic: {
    orientation: "landscape",
    overlay_layout: "corner_hud",
    map_style: "grayscale",
    target_duration: "60",
    map_behavior: "follow_direction",
    fit_full_route: true,
    route_color: "#f97316",
    route_width: "4",
    marker_style: "arrow",
    marker_color: "#f97316",
    overlay_time: true,
    overlay_speed: false,
    overlay_distance: true,
    overlay_track_name: false,
  },
}

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
  ]

  static values = { apiKey: String }

  connect() {
    this.channel = consumer.subscriptions.create(
      { channel: "VideoExportsChannel" },
      { received: (data) => this._handleStatusUpdate(data) },
    )

    this._boundOpen = (e) => this.open(e)
    document.addEventListener("videoExport:open", this._boundOpen)
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
  }

  close() {
    this.modalTarget.classList.remove("modal-open")
    this._resetForm()
  }

  async submit(event) {
    event.preventDefault()

    this._setLoading(true)

    const payload = {
      track_id: this.trackIdInputTarget.value
        ? parseInt(this.trackIdInputTarget.value, 10)
        : null,
      start_at: this.startAtInputTarget.value,
      end_at: this.endAtInputTarget.value,
      config: {
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
      },
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

  // Private methods

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
