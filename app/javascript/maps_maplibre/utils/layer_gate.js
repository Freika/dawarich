/**
 * Layer gating utility for Lite plan users.
 *
 * Provides timed preview behavior for Pro-only map layers (heatmap,
 * fog-of-war, scratch map, globe). When a Lite user toggles a gated
 * layer, it shows for PREVIEW_SECONDS then auto-hides with an upgrade
 * prompt.
 */
import { Toast } from "maps_maplibre/components/toast"
import { UpgradeBanner } from "maps_maplibre/components/upgrade_banner"

const PREVIEW_SECONDS = 20
export const UPGRADE_URL = "https://dawarich.app/pricing"

// Track active preview timers so we can cancel them on manual toggle-off
const activeTimers = {}

/**
 * Check if the current plan is gated (i.e. Lite).
 * Self-hosters and Pro users are never gated.
 */
export function isGatedPlan(userPlan) {
  return userPlan === "lite"
}

/**
 * Wraps a layer toggle with preview gating.
 *
 * @param {string}   layerName   - Display name matching GATED_MAP_LAYERS (e.g. "Heatmap", "Scratch map")
 * @param {string}   userPlan    - Current user plan string
 * @param {HTMLInputElement} toggle - The checkbox element
 * @param {Function} showFn      - Async function that shows/enables the layer
 * @param {Function} hideFn      - Function that hides/disables the layer
 * @returns {boolean} true if the toggle was intercepted (Lite preview), false if normal flow
 */
export function gatedToggle({ layerName, userPlan, toggle, showFn, hideFn }) {
  if (!isGatedPlan(userPlan)) return false

  const enabled = toggle.checked

  // If turning off, cancel any active preview timer and hide
  if (!enabled) {
    cancelPreview(layerName)
    hideFn()
    return true
  }

  // Show the layer as a timed preview
  startPreview({ layerName, toggle, showFn, hideFn })
  return true
}

async function startPreview({ layerName, toggle, showFn, hideFn }) {
  // Cancel any existing preview for this layer
  cancelPreview(layerName)

  Toast.info(`Previewing ${layerName} for ${PREVIEW_SECONDS} seconds.`)

  try {
    await showFn()
  } catch (error) {
    console.error(`Failed to show ${layerName} preview:`, error)
    toggle.checked = false
    return
  }

  activeTimers[layerName] = setTimeout(() => {
    hideFn()
    toggle.checked = false
    delete activeTimers[layerName]

    UpgradeBanner.show({
      message: `${layerName} preview ended.`,
      upgradeUrl: UPGRADE_URL,
      utmContent: `layer_preview_${layerName.toLowerCase().replace(/ /g, "_")}`,
    })
  }, PREVIEW_SECONDS * 1000)
}

function cancelPreview(layerName) {
  if (activeTimers[layerName]) {
    clearTimeout(activeTimers[layerName])
    delete activeTimers[layerName]
  }
}

/**
 * Cancel all active preview timers.
 * Call this from a Stimulus controller's disconnect() to prevent
 * stale timers firing after Turbo Drive navigation.
 */
export function cancelAllPreviews() {
  for (const layerName of Object.keys(activeTimers)) {
    clearTimeout(activeTimers[layerName])
    delete activeTimers[layerName]
  }
}
