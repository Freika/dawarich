import consumer from "../../../channels/consumer"

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
    route_color: "#ffffff",
    route_width: "4",
    marker_style: "arrow",
    overlay_time: true,
    overlay_speed: false,
    overlay_distance: true,
    overlay_track_name: false,
  },
}

/**
 * Video Export Modal - Configuration UI for generating route replay videos
 */
export class VideoExportModal {
  constructor(apiKey) {
    this.apiKey = apiKey
    this.modalElement = null
    this.channel = null
    this._subscribeToUpdates()
  }

  /**
   * Open the video export configuration modal
   * @param {Object} options
   * @param {number} options.trackId - Track ID (null for date range)
   * @param {string} options.startAt - ISO 8601 start timestamp
   * @param {string} options.endAt - ISO 8601 end timestamp
   */
  open({ trackId, startAt, endAt }) {
    this.trackId = trackId
    this.startAt = startAt
    this.endAt = endAt

    this._createModal()
    this.modalElement.showModal()
  }

  close() {
    if (this.modalElement) {
      this.modalElement.close()
      this.modalElement.remove()
      this.modalElement = null
    }
  }

  _createModal() {
    // Remove existing modal if present
    const existing = document.getElementById("video-export-modal")
    if (existing) existing.remove()

    const modal = document.createElement("dialog")
    modal.id = "video-export-modal"
    modal.className = "modal"
    modal.innerHTML = this._buildModalContent()
    document.body.appendChild(modal)
    this.modalElement = modal

    // Bind events
    modal
      .querySelector("#video-export-cancel")
      .addEventListener("click", () => this.close())
    modal
      .querySelector("#video-export-form")
      .addEventListener("submit", (e) => this._handleSubmit(e))
    for (const btn of modal.querySelectorAll("[data-preset]")) {
      btn.addEventListener("click", () => this._applyPreset(btn.dataset.preset))
    }
    modal
      .querySelector('[name="orientation"]')
      .addEventListener("change", (e) =>
        this._onOrientationChange(e.target.value),
      )
    modal.addEventListener("close", () => {
      modal.remove()
      this.modalElement = null
    })
  }

  _buildModalContent() {
    return `
      <div class="modal-box w-11/12 max-w-lg">
        <h3 class="text-lg font-bold mb-4">Generate Route Video</h3>

        <div class="mb-4">
          <label class="label"><span class="label-text font-medium">Quick Presets</span></label>
          <div class="btn-group flex gap-2">
            <button type="button" class="btn btn-sm btn-outline" data-preset="sporty">Sporty</button>
            <button type="button" class="btn btn-sm btn-outline" data-preset="minimal">Minimal</button>
            <button type="button" class="btn btn-sm btn-outline" data-preset="social">Social Story</button>
            <button type="button" class="btn btn-sm btn-outline" data-preset="cinematic">Cinematic</button>
          </div>
        </div>

        <form id="video-export-form" class="space-y-4">
          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Video Title</span>
            </label>
            <input type="text" name="track_name" placeholder="e.g. Morning Run, Weekend Hike" class="input input-bordered w-full" />
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Orientation</span>
            </label>
            <select name="orientation" class="select select-bordered w-full">
              <option value="landscape">Landscape (16:9)</option>
              <option value="portrait">Portrait (9:16)</option>
            </select>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Overlay Layout</span>
            </label>
            <select name="overlay_layout" class="select select-bordered w-full">
              ${this._buildLayoutOptions("landscape")}
            </select>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Map Style</span>
            </label>
            <select name="map_style" class="select select-bordered w-full">
              <option value="dark">Dark</option>
              <option value="light">Light</option>
              <option value="white">White</option>
              <option value="black">Black</option>
              <option value="grayscale">Grayscale</option>
            </select>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Video Duration</span>
            </label>
            <select name="target_duration" class="select select-bordered w-full">
              <option value="15">15 seconds</option>
              <option value="30" selected>30 seconds</option>
              <option value="60">1 minute</option>
              <option value="120">2 minutes</option>
            </select>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Camera Behavior</span>
            </label>
            <select name="map_behavior" class="select select-bordered w-full">
              <option value="north_up">North Up (pan only)</option>
              <option value="follow_direction">Follow Direction (rotate map)</option>
            </select>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Route Color</span>
            </label>
            <input type="color" name="route_color" value="#3b82f6" class="w-12 h-10 cursor-pointer rounded border border-base-300" />
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Line Width</span>
              </label>
              <select name="route_width" class="select select-bordered w-full">
                <option value="2">Thin</option>
                <option value="4" selected>Medium</option>
                <option value="6">Thick</option>
              </select>
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Marker Style</span>
              </label>
              <select name="marker_style" class="select select-bordered w-full">
                <option value="dot" selected>Dot</option>
                <option value="arrow">Arrow</option>
              </select>
            </div>
          </div>

          <div class="form-control">
            <label class="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" name="fit_full_route" class="checkbox checkbox-sm checkbox-primary" />
              <span class="label-text font-medium">Fit full route in view</span>
            </label>
            <label class="label">
              <span class="label-text-alt">Show the entire route at once instead of following the marker</span>
            </label>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Overlays</span>
            </label>
            <div class="space-y-2 ml-1">
              <label class="flex items-center gap-2 cursor-pointer">
                <input type="checkbox" name="overlay_time" checked class="checkbox checkbox-sm checkbox-primary" />
                <span class="label-text">Time</span>
              </label>
              <label class="flex items-center gap-2 cursor-pointer">
                <input type="checkbox" name="overlay_speed" checked class="checkbox checkbox-sm checkbox-primary" />
                <span class="label-text">Speed</span>
              </label>
              <label class="flex items-center gap-2 cursor-pointer">
                <input type="checkbox" name="overlay_distance" checked class="checkbox checkbox-sm checkbox-primary" />
                <span class="label-text">Distance</span>
              </label>
              <label class="flex items-center gap-2 cursor-pointer">
                <input type="checkbox" name="overlay_track_name" checked class="checkbox checkbox-sm checkbox-primary" />
                <span class="label-text">Track Name</span>
              </label>
            </div>
          </div>

          <div class="modal-action">
            <button type="button" id="video-export-cancel" class="btn">Cancel</button>
            <button type="submit" class="btn btn-primary" id="video-export-submit">
              <span id="video-export-submit-text">Generate Video</span>
              <span id="video-export-submit-loading" class="loading loading-spinner loading-sm hidden"></span>
            </button>
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>close</button>
      </form>
    `
  }

  _buildLayoutOptions(orientation) {
    const layouts =
      orientation === "portrait" ? PORTRAIT_LAYOUTS : LANDSCAPE_LAYOUTS
    return layouts
      .map((l) => `<option value="${l.value}">${l.label}</option>`)
      .join("")
  }

  _onOrientationChange(orientation) {
    const select = this.modalElement.querySelector('[name="overlay_layout"]')
    select.innerHTML = this._buildLayoutOptions(orientation)
  }

  _applyPreset(name) {
    const preset = PRESETS[name]
    if (!preset) return
    const form = this.modalElement.querySelector("#video-export-form")

    form.querySelector('[name="orientation"]').value = preset.orientation
    this._onOrientationChange(preset.orientation)
    form.querySelector('[name="overlay_layout"]').value = preset.overlay_layout
    form.querySelector('[name="map_style"]').value = preset.map_style
    form.querySelector('[name="target_duration"]').value =
      preset.target_duration
    form.querySelector('[name="map_behavior"]').value = preset.map_behavior
    form.querySelector('[name="fit_full_route"]').checked =
      preset.fit_full_route
    form.querySelector('[name="route_color"]').value = preset.route_color
    form.querySelector('[name="route_width"]').value = preset.route_width
    form.querySelector('[name="marker_style"]').value = preset.marker_style
    form.querySelector('[name="overlay_time"]').checked = preset.overlay_time
    form.querySelector('[name="overlay_speed"]').checked = preset.overlay_speed
    form.querySelector('[name="overlay_distance"]').checked =
      preset.overlay_distance
    form.querySelector('[name="overlay_track_name"]').checked =
      preset.overlay_track_name
  }

  async _handleSubmit(e) {
    e.preventDefault()
    const form = e.target
    const formData = new FormData(form)

    const submitBtn = document.getElementById("video-export-submit")
    const submitText = document.getElementById("video-export-submit-text")
    const submitLoading = document.getElementById("video-export-submit-loading")

    submitBtn.disabled = true
    submitText.textContent = "Submitting..."
    submitLoading.classList.remove("hidden")

    const payload = {
      track_id: this.trackId || null,
      start_at: this.startAt,
      end_at: this.endAt,
      config: {
        orientation: formData.get("orientation"),
        overlay_layout: formData.get("overlay_layout"),
        map_style: formData.get("map_style"),
        target_duration: parseInt(formData.get("target_duration"), 10),
        map_behavior: formData.get("map_behavior"),
        fit_full_route: formData.has("fit_full_route"),
        route_color: formData.get("route_color"),
        route_width: parseInt(formData.get("route_width"), 10),
        marker_style: formData.get("marker_style"),
        track_name: formData.get("track_name") || "",
        overlays: {
          time: formData.has("overlay_time"),
          speed: formData.has("overlay_speed"),
          distance: formData.has("overlay_distance"),
          track_name: formData.has("overlay_track_name"),
        },
      },
    }

    try {
      const response = await fetch("/api/v1/video_exports", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify(payload),
      })

      if (response.ok) {
        this._showToast(
          "Video export started. You'll be notified when it's ready.",
          "success",
        )
        this.close()
      } else {
        const data = await response.json()
        this._showToast(
          data.errors?.join(", ") || "Failed to start video export",
          "error",
        )
      }
    } catch (error) {
      this._showToast(`Error: ${error.message}`, "error")
    } finally {
      submitBtn.disabled = false
      submitText.textContent = "Generate Video"
      submitLoading.classList.add("hidden")
    }
  }

  _subscribeToUpdates() {
    this.channel = consumer.subscriptions.create(
      { channel: "VideoExportsChannel" },
      {
        received: (data) => this._handleStatusUpdate(data),
      },
    )
  }

  _handleStatusUpdate(data) {
    if (data.status === "completed" && data.download_url) {
      this._showToast(
        `Video "${data.name}" is ready! <a href="${data.download_url}" class="underline font-bold" download>Download</a>`,
        "success",
        10000,
      )
    } else if (data.status === "failed") {
      this._showToast(
        `Video "${data.name}" failed: ${data.error_message || "Unknown error"}`,
        "error",
        10000,
      )
    }
  }

  _showToast(message, type, duration = 5000) {
    const toast = document.createElement("div")
    toast.className = "toast toast-top toast-end z-50"
    toast.innerHTML = `
      <div class="alert alert-${type === "success" ? "success" : "error"}">
        <span>${message}</span>
      </div>
    `
    document.body.appendChild(toast)
    setTimeout(() => toast.remove(), duration)
  }

  destroy() {
    if (this.channel) {
      this.channel.unsubscribe()
      this.channel = null
    }
  }
}
