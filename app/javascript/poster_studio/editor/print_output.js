import Flash from "controllers/flash_controller"
import { translate } from "i18n"
import { resolveLayoutGeometry } from "poster_studio/data/layouts"
import { printProductFor } from "poster_studio/data/print_products"
import { downloadBlob } from "poster_studio/export/download"
import { exportPoster, studioFilename } from "poster_studio/ui/exporter"
import { submitPrintOrder } from "poster_studio/ui/order_client"

/**
 * Poster download and the print order flow (size picker, checkout steps).
 * Mixed into PosterStudioEditorController; `this` is the PosterStudioEditorController.
 */
export const printOutput = {
  async download() {
    if (this.busy || !this.previewMap) return
    try {
      this.setBusy(true)
      const layout = this.layout
      const dpi = Number.parseInt(this.dpiTarget.value, 10)
      const geometry = resolveLayoutGeometry(layout, dpi)
      this.setStatus(
        translate("poster.rendering", {
          width: geometry.width,
          height: geometry.height,
        }),
      )

      const mapBounds = this.previewMap.getBounds()
      const { blob, extension } = await exportPoster({
        style: this.posterStyle(),
        bounds: [
          [mapBounds.getWest(), mapBounds.getSouth()],
          [mapBounds.getEast(), mapBounds.getNorth()],
        ],
        layout,
        dpi,
        format: this.formatTarget.value,
        theme: this.resolvedTheme,
        text: this.posterText(),
        font: this.fontFamily,
        cssSize: {
          width: this.frameTarget.clientWidth,
          height: this.frameTarget.clientHeight,
        },
      })
      downloadBlob(
        blob,
        studioFilename(this.titleInputTarget.value, layout, extension),
      )
      this.setStatus(
        geometry.steppedDown
          ? translate("poster.saved_at_dpi", {
              dpi: geometry.effectiveDpi,
            })
          : translate("poster.saved"),
      )
    } catch (error) {
      Flash.show(
        "error",
        translate("poster.export_failed", { error: error.message }),
      )
      this.setStatus("")
    } finally {
      this.setBusy(false)
    }
  },

  syncOrderAvailability() {
    // The "Order a print" zone appears only when ordering is configured.
    if (!this.hasOrderSectionTarget) return

    this.orderSectionTarget.classList.toggle(
      "hidden",
      this.printOrderUrlValue.length === 0,
    )
  },

  // Exactly one of the three order views shows at a time, so the panel never
  // stacks the CTA, the size picker and the dialog on top of each other.
  showOrderView(which) {
    this.orderCtaTarget.classList.toggle("hidden", which !== "cta")
    this.sizePickerTarget.classList.toggle("hidden", which !== "picker")
    this.orderDialogTarget.classList.toggle("hidden", which !== "dialog")
  },

  openOrder() {
    const product = printProductFor(this.layout.id)
    if (product) this.showOrderDialog(product)
    else this.openSizePicker()
  },

  showOrderDialog(product) {
    this.orderSummaryTarget.textContent = translate("poster.order_summary", {
      layout: translate(`poster.layouts.${this.layout.id}`),
      price: product.priceLabel,
    })
    this.orderErrorTarget.classList.add("hidden")
    this.resetOrderSteps()
    this.showOrderView("dialog")
  },

  closeOrder() {
    this.showOrderView("cta")
  },

  openSizePicker() {
    this.showOrderView("picker")
  },

  closeSizePicker() {
    this.showOrderView("cta")
  },

  pickPrintSize(event) {
    const id = event.currentTarget.dataset.layoutId
    this.layoutSelectTarget.value = id
    // layoutChanged reopens the order view for the now-orderable size.
    this.layoutChanged()
  },

  async confirmOrder() {
    if (this.busy || !this.previewMap) return
    const layout = this.layout
    const product = printProductFor(layout.id)
    if (!product) return

    try {
      this.setBusy(true)
      this.orderErrorTarget.classList.add("hidden")
      this.beginOrderSteps()

      const mapBounds = this.previewMap.getBounds()
      const { blob } = await exportPoster({
        style: this.posterStyle(),
        bounds: [
          [mapBounds.getWest(), mapBounds.getSouth()],
          [mapBounds.getEast(), mapBounds.getNorth()],
        ],
        layout,
        dpi: 300,
        format: "pdf",
        theme: this.resolvedTheme,
        text: this.posterText(),
        font: this.fontFamily,
        cssSize: {
          width: this.frameTarget.clientWidth,
          height: this.frameTarget.clientHeight,
        },
      })

      this.setOrderStep("prepare", "done")
      this.setOrderStep("upload", "active")
      const { token, checkoutUrl } = await submitPrintOrder({
        url: this.printOrderUrlValue,
        blob,
        sku: product.sku,
        title: this.titleInputTarget.value.trim(),
        themeBase: this.themeBase,
        layoutId: layout.id,
        onProgress: (fraction) => {
          this.uploadBarTarget.value = Math.round(fraction * 100)
        },
      })

      this.setOrderStep("upload", "done")
      this.enableCheckout(checkoutUrl, token)
    } catch (error) {
      this.resetOrderSteps()
      this.orderErrorTarget.textContent = error.message
      this.orderErrorTarget.classList.remove("hidden")
    } finally {
      this.setBusy(false)
    }
  },

  // The checkout link is a real user-clicked anchor: window.open after the
  // long render/upload would land outside the popup-blocker gesture window.
  beginOrderSteps() {
    this.orderActionsTarget.classList.add("hidden")
    this.orderStepsTarget.classList.remove("hidden")
    this.uploadBarTarget.value = 0
    this.setOrderStep("prepare", "active")
    this.setOrderStep("upload", "pending")
    this.setOrderStep("checkout", "pending")
    this.checkoutLinkTarget.classList.add("btn-disabled")
    this.checkoutLinkTarget.setAttribute("aria-disabled", "true")
    this.checkoutLinkTarget.removeAttribute("href")
    this.orderPageLinkTarget.classList.add("hidden")
    this.orderDoneButtonTarget.classList.add("hidden")
  },

  resetOrderSteps() {
    this.orderStepsTarget.classList.add("hidden")
    this.orderActionsTarget.classList.remove("hidden")
  },

  setOrderStep(name, state) {
    const step = this.orderStepTargets.find((el) => el.dataset.step === name)
    if (!step) return
    step.classList.toggle("opacity-40", state === "pending")
    step
      .querySelector("[data-role='spinner']")
      ?.classList.toggle("hidden", state !== "active")
    step
      .querySelector("[data-role='done']")
      ?.classList.toggle("hidden", state !== "done")
    step
      .querySelector("[data-role='bar']")
      ?.classList.toggle("hidden", state !== "active")
  },

  enableCheckout(checkoutUrl, token) {
    this.setOrderStep("checkout", "active")
    this.checkoutLinkTarget.href = checkoutUrl
    this.checkoutLinkTarget.classList.remove("btn-disabled")
    this.checkoutLinkTarget.removeAttribute("aria-disabled")
    if (token) {
      this.orderPageLinkTarget.href = `${new URL(this.printOrderUrlValue).origin}/orders/${token}`
      this.orderPageLinkTarget.classList.remove("hidden")
    }
    this.orderDoneButtonTarget.classList.remove("hidden")
  },
}
