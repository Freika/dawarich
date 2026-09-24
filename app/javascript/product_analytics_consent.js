// Runs without analytics SDKs. Third-party scripts are inserted only after an
// explicit Cloud choice; account choices override this browser's local choice.
function initializeProductAnalyticsConsent() {
  const root = document.documentElement
  if (root.dataset.selfHosted === "true") return

  const storageKey = "dawarich_product_analytics_consent_v1"
  const panel = document.getElementById("product-analytics-choice")
  if (!panel || panel.dataset.initialized === "true") return
  panel.dataset.initialized = "true"
  const error = document.getElementById("product-analytics-choice-error")
  const open = document.getElementById("product-analytics-choice-open")
  const csrf = document.querySelector('meta[name="csrf-token"]')?.content
  const account = root.dataset.analyticsAccount === "true"
  const serverChoice = root.dataset.analyticsConsent
  const savedChoice = localStorage.getItem(storageKey)
  document.querySelectorAll("[data-product-analytics-consent-field]").forEach((field) => {
    field.value = ["true", "false"].includes(savedChoice) ? savedChoice : ""
  })

  function addScript(src, attributes = {}) {
    const script = document.createElement("script")
    script.src = src
    script.async = true
    Object.entries(attributes).forEach(([name, value]) => script.setAttribute(name, value))
    document.head.appendChild(script)
  }

  function startConsentedScripts() {
    if (window.__dawarichConsentedScriptsStarted) return
    window.__dawarichConsentedScriptsStarted = true
    addScript("https://scripts.simpleanalyticscdn.com/latest.js")
    addScript("https://rybbit.dwri.xyz/api/script.js", { "data-site-id": "87c1f532b59f" })

    const partneroId = root.dataset.partneroId
    if (partneroId) {
      function makeQueue(queue) {
        return function () {
          const call = { a: arguments, q: [] }
          const index = queue.push(call)
          return typeof index === "number" ? makeQueue(call.q) : index
        }
      }
      const calls = []
      const po = makeQueue(calls)
      po.q = calls
      window.__partnerObject = "po"
      window.po = po
      addScript("https://app.partnero.com/js/universal.js")
      po("settings", "assets_host", "https://assets.partnero.com")
      po("program", partneroId, "load")
    }

    const googleAdsId = root.dataset.googleAdsId
    if (googleAdsId && /^[A-Z]{2}-[A-Z0-9-]+$/.test(googleAdsId)) {
      window.dataLayer = window.dataLayer || []
      window.gtag = function () { window.dataLayer.push(arguments) }
      window.gtag("js", new Date())
      window.gtag("config", googleAdsId, { send_page_view: false })
      addScript(`https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(googleAdsId)}`)
    }

    if (account && csrf) {
      fetch("/product_analytics_events", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
        body: JSON.stringify({ event: "web_first_observed" }),
        credentials: "same-origin"
      }).catch(() => {})
    }
  }

  async function save(choice) {
    error.hidden = true
    try {
      if (account) {
        const response = await fetch("/product_analytics_consent", {
          method: "PATCH",
          headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
          body: JSON.stringify({ consent: choice }),
          credentials: "same-origin"
        })
        if (!response.ok) throw new Error("Consent request failed")
      }
      localStorage.setItem(storageKey, String(choice))
      location.reload()
    } catch {
      error.hidden = false
    }
  }

  panel?.querySelectorAll("[data-analytics-choice]").forEach((button) => {
    button.addEventListener("click", () => save(button.dataset.analyticsChoice === "true"))
  })
  open?.addEventListener("click", () => { panel.hidden = false; panel.scrollIntoView() })

  const choice = account ? serverChoice : savedChoice
  if (choice === "true") startConsentedScripts()
  if (choice !== "true" && choice !== "false") panel.hidden = false
}

document.addEventListener("turbo:load", initializeProductAnalyticsConsent)
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initializeProductAnalyticsConsent)
} else {
  initializeProductAnalyticsConsent()
}
