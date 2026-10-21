import { studioQueryAll, studioValue } from "../studios/dom.js"
import { PRINT_PRODUCTS, printProductFor } from "./data/print_products.js"
import { submitPrintOrder } from "./order.js"
import { interpolate } from "./strings.js"

const ERROR_CODES = [
  "wrong_size",
  "too_large",
  "unknown_sku",
  "payment_unavailable",
  "not_pdf",
  "unreadable",
  "generic",
  "connection",
]
const CHECKOUT_HOSTS = ["checkout.stripe.com"]

export function approvedCheckoutUrl(value, printOrderUrl) {
  try {
    const url = new URL(value)
    const hosts = [new URL(printOrderUrl).host, ...CHECKOUT_HOSTS]
    return url.protocol === "https:" && hosts.includes(url.host)
      ? url.href
      : null
  } catch {
    return null
  }
}

export function bindOrderControls({
  root,
  find,
  on,
  studio,
  exports,
  strings = {},
  printOrderUrl = "",
  loadLibrary,
  maxDimensionPx,
  submit = submitPrintOrder,
  layoutLabel,
}) {
  const errors = Object.fromEntries(
    ERROR_CODES.map((code) => [code, strings[`order_errors.${code}`]]),
  )
  let current = null

  find("order-section")?.classList.toggle("hidden", !printOrderUrl)
  const sizes = [...studioQueryAll(root, "[data-poster-print-size]")]
  for (const size of sizes) {
    const price = size.querySelector("[data-poster-print-price]")
    if (price)
      price.textContent =
        PRINT_PRODUCTS[studioValue(size, "posterPrintSize")].priceLabel
    on(size, "click", () => {
      const layout = find("layout")
      if (!layout) return
      layout.value = studioValue(size, "posterPrintSize")
      layout.dispatchEvent(new Event("change"))
    })
  }

  const hidden = (name, value) => find(name)?.classList.toggle("hidden", value)
  const view = (which) => {
    hidden("order-cta", which !== "cta")
    hidden("size-picker", which !== "picker")
    hidden("order-dialog", which !== "dialog")
  }
  const viewOpen = () =>
    find("order-dialog")?.classList.contains("hidden") === false ||
    find("size-picker")?.classList.contains("hidden") === false

  function setStep(name, state) {
    const element = [...studioQueryAll(root, "[data-poster-order-step]")].find(
      (candidate) => studioValue(candidate, "posterOrderStep") === name,
    )
    if (!element) return
    element.classList.toggle("opacity-40", state === "pending")
    for (const [role, visible] of [
      ["spinner", state === "active"],
      ["done", state === "done"],
      ["bar", state === "active"],
    ])
      element
        .querySelector(`[data-role='${role}']`)
        ?.classList.toggle("hidden", !visible)
  }

  function resetSteps() {
    hidden("order-steps", true)
    hidden("order-actions", false)
  }

  function beginSteps() {
    hidden("order-actions", true)
    hidden("order-steps", false)
    const bar = find("upload-bar")
    if (bar) bar.value = 0
    setStep("prepare", "active")
    setStep("upload", "pending")
    setStep("checkout", "pending")
    const checkout = find("checkout")
    if (checkout) {
      checkout.classList.add("btn-disabled")
      checkout.setAttribute("aria-disabled", "true")
      checkout.removeAttribute("href")
      delete checkout.href
    }
    hidden("order-page", true)
    hidden("order-done", true)
  }

  function enableCheckout(checkoutUrl, token) {
    setStep("checkout", "active")
    const checkout = find("checkout")
    if (checkout) {
      checkout.href = checkoutUrl
      checkout.classList.remove("btn-disabled")
      checkout.removeAttribute("aria-disabled")
    }
    const page = find("order-page")
    if (token && page) {
      page.href = `${new URL(printOrderUrl).origin}/orders/${token}`
      page.classList.remove("hidden")
    }
    hidden("order-done", false)
  }

  function open() {
    const id = studio.state.layoutId
    const product = printProductFor(id)
    if (!product) return view("picker")
    const summary = find("order-summary")
    if (summary)
      summary.textContent = interpolate(strings.order_summary, {
        layout: layoutLabel(id),
        price: product.priceLabel,
      })
    hidden("order-error", true)
    resetSteps()
    view("dialog")
  }

  const setDownloadBusy = (busy) => {
    const download = find("download")
    if (download) download.disabled = busy
  }

  async function confirm() {
    const request = studio.exportRequest()
    const product = printProductFor(studio.state.layoutId)
    if (!request || !product || current || exports.busy) return
    const operation = { controller: new AbortController() }
    current = operation
    setDownloadBusy(true)
    hidden("order-error", true)
    beginSteps()
    try {
      const library = await loadLibrary()
      const rendered = await exports.run(
        { ...request, dpi: 300, format: "pdf", library, maxDimensionPx },
        { deliver: false },
      )
      if (current !== operation || rendered.status === "cancelled") return
      if (rendered.status !== "done") throw rendered.error
      setStep("prepare", "done")
      setStep("upload", "active")
      const { token, checkoutUrl } = await submit({
        url: printOrderUrl,
        blob: rendered.blob,
        sku: product.sku,
        title: studio.state.title.trim(),
        themeBase: studio.state.themeKey,
        layoutId: studio.state.layoutId,
        onProgress: (fraction) => {
          const bar = find("upload-bar")
          if (bar && current === operation)
            bar.value = Math.round(fraction * 100)
        },
        signal: operation.controller.signal,
        errors,
      })
      if (current !== operation) return
      const approved = approvedCheckoutUrl(checkoutUrl, printOrderUrl)
      if (!approved) throw new Error(errors.generic || "")
      setStep("upload", "done")
      enableCheckout(approved, token)
    } catch (error) {
      if (current !== operation || error?.name === "AbortError") return
      resetSteps()
      const message = find("order-error")
      if (message) {
        message.textContent = error?.message || errors.generic || ""
        message.classList.remove("hidden")
      }
    } finally {
      if (current === operation) {
        current = null
        setDownloadBusy(exports.busy)
      }
    }
  }

  function cancel() {
    if (!current) return
    current.controller.abort()
    current = null
    resetSteps()
    setDownloadBusy(exports.busy)
  }

  on(find("order-open"), "click", open)
  on(find("order-back"), "click", () => view("picker"))
  on(find("size-cancel"), "click", () => view("cta"))
  on(find("order-done"), "click", () => view("cta"))
  on(find("order-confirm"), "click", () => confirm())
  on(find("layout"), "change", () => {
    if (viewOpen() && !current && !exports.busy) open()
  })

  return { cancel, open }
}
