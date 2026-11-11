import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"

// Polling interval for recalculation status (5 seconds)
const RECALCULATION_POLL_INTERVAL = 5000

/** The transportation-mode form and the recalculation it can start. */
export class TransportationSettings {
  constructor(controller) {
    this.controller = controller
    this.recalculationPollTimer = null
    this.transportationSettingsDirty = false
    this.isTransportationSettingsLocked = false
  }

  get settings() {
    return this.controller.settings
  }

  async syncTransportationSettings() {
    const controller = this.controller

    // Sync enabled transportation modes allowlist
    if (controller.hasEnabledModeCheckboxTarget) {
      const enabled = this.settings.enabledTransportationModes
      if (Array.isArray(enabled)) {
        const enabledSet = new Set(enabled.map(String))
        controller.enabledModeCheckboxTargets.forEach((checkbox) => {
          checkbox.checked = enabledSet.has(checkbox.value)
        })
      }
    }

    // Check recalculation status and update UI accordingly
    // This will also handle locking the form if recalculation is in progress
    await this.checkRecalculationStatus()

    // Only reset dirty state if not locked (recalculation not in progress)
    // The lock state is set by checkRecalculationStatus -> updateRecalculationUI
    if (!this.isTransportationSettingsLocked) {
      this.resetTransportationDirtyState()
    }
  }

  /**
   * Reset transportation settings dirty state
   */
  resetTransportationDirtyState() {
    this.transportationSettingsDirty = false
    this.updateTransportationApplyButton()
    document.dispatchEvent(
      new CustomEvent("map-settings:saved", {
        detail: { scope: "transportation" },
      }),
    )
  }

  /**
   * Update the apply button state based on dirty flag
   */
  updateTransportationApplyButton() {
    const controller = this.controller

    if (controller.hasTransportationApplyButtonTarget) {
      controller.transportationApplyButtonTarget.disabled =
        !this.transportationSettingsDirty
    }

    if (controller.hasTransportationDirtyMessageTarget) {
      if (this.transportationSettingsDirty) {
        controller.transportationDirtyMessageTarget.textContent = translate(
          "settings.unsaved_transportation_changes",
        )
        controller.transportationDirtyMessageTarget.classList.add(
          "text-warning",
        )
        controller.transportationDirtyMessageTarget.classList.remove(
          "text-base-content/60",
        )
      } else {
        controller.transportationDirtyMessageTarget.textContent = translate(
          "settings.make_changes_to_apply",
        )
        controller.transportationDirtyMessageTarget.classList.remove(
          "text-warning",
        )
        controller.transportationDirtyMessageTarget.classList.add(
          "text-base-content/60",
        )
      }
    }
  }

  /**
   * Mark transportation settings as dirty (changed but not saved)
   */
  markTransportationSettingsDirty() {
    this.transportationSettingsDirty = true
    this.updateTransportationApplyButton()
  }

  /**
   * Apply transportation settings with confirmation
   */
  async applyTransportationSettings() {
    // Show confirmation dialog
    const confirmed = confirm(
      translate("settings.confirm_transportation_recalculation"),
    )

    if (!confirmed) return

    await this.saveEnabledTransportationModes()
  }

  /**
   * Save the enabled transportation modes allowlist to backend.
   * (Threshold settings are gone — detection tunes itself.)
   */
  async saveEnabledTransportationModes() {
    const controller = this.controller

    if (!controller.hasEnabledModeCheckboxTarget) return

    const enabledTransportationModes = controller.enabledModeCheckboxTargets
      .filter((checkbox) => checkbox.checked)
      .map((checkbox) => checkbox.value)

    this.settings.enabledTransportationModes = enabledTransportationModes

    const result = await SettingsManager.updateSetting(
      "enabledTransportationModes",
      enabledTransportationModes,
    )

    // Check result and update UI
    if (result && result.status === "locked") {
      Toast.error(
        translate(
          "messages.cannot_update_recalculation_is_already_in_progress",
        ),
      )
      // Immediately lock the UI
      this.setTransportationSettingsLocked(true)
      // Also start polling for status updates
      this.startRecalculationPolling()
      return
    }

    if (result?.recalculation_triggered) {
      Toast.info(translate("settings.transportation_recalculation_started"))
      this.resetTransportationDirtyState()
      // Immediately lock the UI since recalculation started
      this.setTransportationSettingsLocked(true)
      // Start polling for status updates
      this.startRecalculationPolling()
    } else {
      Toast.success(translate("messages.transportation_settings_saved"))
      this.resetTransportationDirtyState()
    }
  }

  // ===== Transportation Mode Recalculation Status =====

  /**
   * Check the transportation mode recalculation status
   */
  async checkRecalculationStatus() {
    try {
      const apiKey = this.controller.apiKeyValue
      if (!apiKey) {
        console.warn(
          "[Settings] No API key available for recalculation status check",
        )
        return
      }

      const response = await fetch(
        "/api/v1/settings/transportation_recalculation_status",
        {
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
          },
        },
      )

      if (!response.ok) {
        console.warn(
          "[Settings] Failed to check recalculation status:",
          response.status,
        )
        return
      }

      const data = await response.json()
      this.updateRecalculationUI(data)
    } catch (error) {
      console.error("[Settings] Error checking recalculation status:", error)
    }
  }

  /**
   * Update UI based on recalculation status
   */
  updateRecalculationUI(status) {
    const controller = this.controller
    const isProcessing = status.status === "processing"
    const isCompleted = status.status === "completed"
    const isFailed = status.status === "failed"

    // Update locked state
    this.setTransportationSettingsLocked(isProcessing)

    // Update status alert
    if (controller.hasTransportationRecalculationAlertTarget) {
      const alertEl = controller.transportationRecalculationAlertTarget

      // Clear existing content
      alertEl.textContent = ""

      if (isProcessing) {
        const progress =
          status.total_tracks > 0
            ? Math.round((status.processed_tracks / status.total_tracks) * 100)
            : 0

        const processedFormatted = (
          status.processed_tracks || 0
        ).toLocaleString()
        const totalFormatted = (status.total_tracks || 0).toLocaleString()

        // Create inline container for spinner and text
        const container = document.createElement("span")
        container.className = "inline-flex items-center gap-2"

        const spinner = document.createElement("span")
        spinner.className = "loading loading-spinner loading-xs"

        const text = document.createElement("span")
        text.textContent = translate(
          "settings.transportation_recalculation_progress",
          {
            processed: processedFormatted,
            total: totalFormatted,
            progress,
          },
        )

        container.appendChild(spinner)
        container.appendChild(text)
        alertEl.appendChild(container)
        alertEl.classList.remove("hidden", "alert-success", "alert-error")
        alertEl.classList.add("alert-warning")
      } else if (isCompleted) {
        const text = document.createElement("span")
        text.textContent = translate(
          "settings.transportation_recalculation_completed",
        )

        alertEl.appendChild(text)
        alertEl.classList.remove("hidden", "alert-warning", "alert-error")
        alertEl.classList.add("alert-success")
        // Auto-hide after 5 seconds
        setTimeout(() => alertEl.classList.add("hidden"), 5000)
        // Reset dirty state so apply button shows correct message
        this.resetTransportationDirtyState()
      } else if (isFailed) {
        const text = document.createElement("span")
        text.textContent = translate(
          "settings.transportation_recalculation_failed",
          {
            error: status.error_message || translate("common.unknown_error"),
          },
        )

        alertEl.appendChild(text)
        alertEl.classList.remove("hidden", "alert-warning", "alert-success")
        alertEl.classList.add("alert-error")
      } else {
        alertEl.classList.add("hidden")
      }
    }

    // Start or stop polling based on status
    if (isProcessing) {
      this.startRecalculationPolling()
    } else {
      this.stopRecalculationPolling()
    }
  }

  /**
   * Set transportation settings to locked or unlocked state
   */
  setTransportationSettingsLocked(locked) {
    // Track the locked state
    this.isTransportationSettingsLocked = locked

    const controller = this.controller

    // Lock the enabled-mode checkboxes
    if (controller.hasEnabledModeCheckboxTarget) {
      controller.enabledModeCheckboxTargets.forEach((checkbox) => {
        checkbox.disabled = locked
        checkbox.classList.toggle("opacity-50", locked)
        checkbox.classList.toggle("cursor-not-allowed", locked)
      })
    }

    // Also disable/enable the apply button
    if (controller.hasTransportationApplyButtonTarget) {
      controller.transportationApplyButtonTarget.disabled = locked
      if (locked) {
        controller.transportationApplyButtonTarget.classList.add("btn-disabled")
      } else {
        controller.transportationApplyButtonTarget.classList.remove(
          "btn-disabled",
        )
      }
    }

    // Update locked message visibility
    if (controller.hasTransportationLockedMessageTarget) {
      controller.transportationLockedMessageTarget.classList.toggle(
        "hidden",
        !locked,
      )
    }

    // Update dirty message visibility (hide when locked)
    if (controller.hasTransportationDirtyMessageTarget) {
      controller.transportationDirtyMessageTarget.classList.toggle(
        "hidden",
        locked,
      )
    }
  }

  /**
   * Start polling for recalculation status
   */
  startRecalculationPolling() {
    if (this.recalculationPollTimer) return // Already polling

    this.recalculationPollTimer = setInterval(() => {
      this.checkRecalculationStatus()
    }, RECALCULATION_POLL_INTERVAL)
  }

  /**
   * Stop polling for recalculation status
   */
  stopRecalculationPolling() {
    if (this.recalculationPollTimer) {
      clearInterval(this.recalculationPollTimer)
      this.recalculationPollTimer = null
    }
  }
}
