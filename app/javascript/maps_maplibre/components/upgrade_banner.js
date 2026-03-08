/**
 * Persistent, dismissible map overlay banner for upgrade prompts.
 * Singleton: only one banner is visible at a time.
 */
export class UpgradeBanner {
  static activeBanner = null

  /**
   * Show an upgrade banner on the map.
   * Replaces any existing banner.
   *
   * @param {Object} options
   * @param {string} options.message - Plain text message to display
   * @param {string} options.upgradeUrl - Base URL for the upgrade link
   * @param {string} options.utmContent - UTM content tag for tracking
   * @returns {HTMLElement} The banner element
   */
  static show({ message, upgradeUrl, utmContent }) {
    if (sessionStorage.getItem("upgrade_banner_dismissed")) return null

    UpgradeBanner.dismiss()

    // Remove any server-rendered banner so only one is visible at a time
    document.querySelectorAll(".map-upgrade-banner").forEach((el) => {
      el.remove()
    })

    const url = `${upgradeUrl}?utm_source=app&utm_medium=map_banner&utm_content=${encodeURIComponent(utmContent)}`

    const banner = document.createElement("div")
    banner.className = "map-upgrade-banner"
    banner.setAttribute("role", "status")
    banner.setAttribute("aria-live", "polite")

    const infoIcon = document.createElement("span")
    infoIcon.className = "map-upgrade-banner-icon"
    infoIcon.setAttribute("aria-hidden", "true")
    infoIcon.innerHTML =
      '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>'

    const text = document.createElement("span")
    text.className = "map-upgrade-banner-text"
    text.textContent = message

    const cta = document.createElement("a")
    cta.className = "btn btn-sm btn-primary map-upgrade-banner-cta"
    cta.href = url
    cta.target = "_blank"
    cta.rel = "noopener noreferrer"
    cta.textContent = "Upgrade to Pro"

    const dismissBtn = document.createElement("button")
    dismissBtn.className = "map-upgrade-banner-dismiss"
    dismissBtn.setAttribute("aria-label", "Dismiss")
    dismissBtn.textContent = "\u2715"
    dismissBtn.addEventListener("click", () => UpgradeBanner.dismiss())

    banner.append(infoIcon, text, cta, dismissBtn)

    // Insert into the map container or fall back to body
    const mapContainer =
      document.getElementById("maps-maplibre-container") ||
      document.getElementById("map") ||
      document.body
    mapContainer.appendChild(banner)

    UpgradeBanner.activeBanner = banner
    return banner
  }

  /**
   * Dismiss the active banner, if any.
   */
  static dismiss() {
    if (UpgradeBanner.activeBanner) {
      UpgradeBanner.activeBanner.remove()
      UpgradeBanner.activeBanner = null
      sessionStorage.setItem("upgrade_banner_dismissed", "1")
    }
  }
}
