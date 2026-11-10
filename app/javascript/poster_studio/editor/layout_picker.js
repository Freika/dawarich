import { translate } from "i18n"
import {
  DEFAULT_FONT_KEY,
  ensurePosterFont,
  POSTER_FONTS,
} from "poster_studio/data/fonts"
import {
  DEFAULT_LAYOUT_ID,
  LAYOUT_CATEGORIES,
  layoutById,
} from "poster_studio/data/layouts"
import {
  ORDERABLE_LAYOUT_IDS,
  PRINT_PRODUCTS,
} from "poster_studio/data/print_products"
import { fitFrame } from "poster_studio/ui/preview"

/**
 * Poster layout, print size and font pickers, and the frame resize.
 * Mixed into PosterStudioEditorController; `this` is the PosterStudioEditorController.
 */
export const layoutPicker = {
  // ===== Layout =====
  populateLayouts() {
    const select = this.layoutSelectTarget
    select.innerHTML = ""
    LAYOUT_CATEGORIES.forEach((category) => {
      const group = document.createElement("optgroup")
      group.label = translate(`poster.categories.${category.id}`)
      category.layouts.forEach((layout) => {
        const option = document.createElement("option")
        option.value = layout.id
        option.textContent = translate(`poster.layouts.${layout.id}`)
        group.appendChild(option)
      })
      select.appendChild(group)
    })
    select.value = DEFAULT_LAYOUT_ID
  },

  populateSizePicker() {
    if (!this.hasSizePickerOptionsTarget) return

    const container = this.sizePickerOptionsTarget
    container.innerHTML = ""
    ORDERABLE_LAYOUT_IDS.forEach((id) => {
      const layout = layoutById(id)
      const button = document.createElement("button")
      button.type = "button"
      button.className = "btn btn-outline btn-sm w-full justify-between"
      button.dataset.layoutId = id
      button.dataset.action = "poster-studio-editor#pickPrintSize"

      const name = document.createElement("span")
      name.textContent = translate(`poster.layouts.${layout.id}`)
      const price = document.createElement("span")
      price.className = "opacity-70"
      price.textContent = PRINT_PRODUCTS[id].priceLabel
      button.append(name, price)
      container.appendChild(button)
    })
  },

  layoutChanged() {
    this.resizeFrame()
    this.updateSummary()
    this.syncOrderAvailability()
    // Keep an open order view in sync with the new size: an orderable size
    // refreshes the dialog (and its price); a non-orderable one falls back to
    // the size picker. Skipped while an order is rendering/uploading so the
    // step list isn't reset mid-flight.
    if (this.orderViewOpen && !this.busy) this.openOrder()
  },

  resizeFrame() {
    const layout = this.layout
    const { width, height } = fitFrame(this.stageTarget, layout.aspect)
    this.frameTarget.style.width = `${width}px`
    this.frameTarget.style.height = `${height}px`
    this.layoutDimsTarget.textContent = layout.dimensionsLabel
    this.previewMap?.resize()
    this.redrawOverlay()

    const isPaper = layout.kind === "paper"
    this.dpiFieldTarget.classList.toggle("invisible", !isPaper)
    const pdfOption = this.formatTarget.querySelector('option[value="pdf"]')
    pdfOption.disabled = !isPaper
    if (!isPaper && this.formatTarget.value === "pdf")
      this.formatTarget.value = "png"
  },

  // ===== Text =====

  populateFonts() {
    const select = this.fontSelectTarget
    select.innerHTML = ""
    POSTER_FONTS.forEach((font) => {
      const option = document.createElement("option")
      option.value = font.key
      option.textContent = font.label
      option.style.fontFamily = `"${font.family}", sans-serif`
      select.appendChild(option)
    })
    select.value = DEFAULT_FONT_KEY
  },

  async loadFonts() {
    await Promise.allSettled(
      POSTER_FONTS.map((font) => ensurePosterFont(font.key, this.fontsValue)),
    )
  },
}
