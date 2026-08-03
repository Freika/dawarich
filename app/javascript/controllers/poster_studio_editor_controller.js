import { Controller } from "@hotwired/stimulus"
import { translate } from "i18n"
import {
  DEFAULT_FONT_KEY,
  ensurePosterFont,
  fontByKey,
  POSTER_FONTS,
} from "poster_studio/data/fonts"
import {
  DEFAULT_LAYOUT_ID,
  LAYOUT_CATEGORIES,
  layoutById,
  resolveLayoutGeometry,
} from "poster_studio/data/layouts"
import {
  ORDERABLE_LAYOUT_IDS,
  PRINT_PRODUCTS,
  printProductFor,
} from "poster_studio/data/print_products"
import { MapPageProvider } from "poster_studio/data/providers"
import {
  extendTokens,
  loadThemeTokens,
  resolveTheme,
} from "poster_studio/data/theme_loader"
import { downloadBlob } from "poster_studio/export/download"
import { frameCovers } from "poster_studio/render/frame_geometry"
import { drawOverlay } from "poster_studio/render/overlay"
import { buildPosterStyle } from "poster_studio/render/style_builder"
import { formatCoords } from "poster_studio/render/text_layout"
import { exportPoster, studioFilename } from "poster_studio/ui/exporter"
import { submitPrintOrder } from "poster_studio/ui/order_client"
import {
  collectCoords,
  createPreviewMap,
  fitFrame,
  trackBounds,
} from "poster_studio/ui/preview"
import Flash from "./flash_controller"

const RESTYLE_DEBOUNCE_MS = 150
const DEFAULT_HIDDEN = ["buildings", "rail", "boundaries"]
const METERS_PER_DEGREE = 111320
// Sidecar frame semantics: it renders ±distance/3 vertically, so covering
// the studio's visible height needs distance = 3 × half-height in meters.
const SIDECAR_DISTANCE_FACTOR = 1.5
// Max lifted so any single-view framing is saveable: the distance box is
// calibrated to the visible frame, so a low cap made zoomed-out routes read as
// "outside the frame" even while visible. The upper bound stays finite to keep
// degenerate whole-globe requests off the sidecar.
const SIDECAR_DISTANCE_RANGE = [500, 5_000_000]
function toLocalInput(date) {
  const pad = (n) => String(n).padStart(2, "0")
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`
}

// Full-screen WYSIWYG poster editor: a live MapLibre map inside a
// poster-shaped frame, restyled by the same buildPosterStyle the export
// renders, with typography drawn by the same overlay pass — so what the
// preview shows is what the download produces.
export default class extends Controller {
  static targets = [
    "stage",
    "frame",
    "mapContainer",
    "overlay",
    "backdrop",
    "layoutSelect",
    "layoutDims",
    "swatch",
    "themeLabel",
    "token",
    "tokenValue",
    "textToggle",
    "titleInput",
    "subtitleInput",
    "coordsToggle",
    "fontSelect",
    "trackOpacity",
    "trackOpacityLabel",
    "trackWidth",
    "trackWidthLabel",
    "summary",
    "format",
    "dpi",
    "dpiField",
    "downloadButton",
    "status",
    "saveButton",
    "saveNotice",
    "saveForm",
    "saveName",
    "saveTitle",
    "saveTheme",
    "saveLat",
    "saveLon",
    "saveDistance",
    "saveStartAt",
    "saveEndAt",
    "saveSource",
    "saveOpacity",
    "saveWidth",
    "dateStart",
    "dateEnd",
    "loadButton",
    "loadSpinner",
    "loadLabel",
    "orderSection",
    "orderCta",
    "orderButton",
    "sizePicker",
    "sizePickerOptions",
    "orderDialog",
    "orderSummary",
    "orderError",
    "orderActions",
    "orderSteps",
    "orderStep",
    "uploadBar",
    "checkoutLink",
    "orderPageLink",
    "orderDoneButton",
  ]
  static values = { fonts: Object, printOrderUrl: String }

  connect() {
    // The map page wraps content in a z-index:20 stacking context that would
    // trap the overlay under the navbar — portal to <body>. Moving the node
    // re-runs connect (Stimulus disconnect/reconnect), hence the guard.
    if (this.element.parentElement !== document.body) {
      document.body.appendChild(this.element)
      return
    }
    this.onOpen = (event) => this.open(event.detail?.provider)
    document.addEventListener("poster-studio:open", this.onOpen)
    this.onResize = () => this.resizeFrame()
    this.populateLayouts()
    this.populateSizePicker()
    this.populateFonts()
    this.trackOpacityLabelTarget.textContent = `${this.trackOpacityTarget.value}%`
    this.trackWidthLabelTarget.textContent = `${this.trackWidthTarget.value}%`
  }

  disconnect() {
    document.removeEventListener("poster-studio:open", this.onOpen)
    this.teardown()
    if (this.backdropUrl) URL.revokeObjectURL(this.backdropUrl)
  }

  async open(provider = null) {
    if (!this.element.classList.contains("hidden")) return
    this.provider =
      provider ?? new MapPageProvider({ application: this.application })
    this.element.classList.remove("hidden")
    window.addEventListener("resize", this.onResize)

    try {
      this.hidden ??= new Set(DEFAULT_HIDDEN)
      if (!this.tokens) await this.seedTheme(this.initialThemeKey())
      if (!this.titleInputTarget.value)
        this.titleInputTarget.value = this.provider.defaultTitle()
      if (!this.subtitleInputTarget.value)
        this.subtitleInputTarget.value = this.dateRangeLabel()
      this.seedDateInputs()

      this.resizeFrame()
      await this.loadFonts()
      this.createMap()
      this.updateSummary()
      this.syncOrderAvailability()
    } catch (error) {
      Flash.show(
        "error",
        translate("poster.open_failed", { error: error.message }),
      )
      this.close()
    }
  }

  close() {
    window.removeEventListener("resize", this.onResize)
    this.teardown()
    this.releaseBackdrop()
    this.element.classList.add("hidden")
  }

  teardown() {
    clearTimeout(this.restyleTimer)
    this.previewMap?.remove()
    this.previewMap = null
  }

  createMap() {
    this.teardown()
    const bounds =
      trackBounds(this.trackGeojson) ?? this.provider.fallbackBounds()
    this.previewMap = createPreviewMap({
      container: this.mapContainerTarget,
      style: this.posterStyle(),
      bounds,
    })
    this.previewMap.on("move", () => this.redrawOverlay())
    this.previewMap.on("moveend", () => this.syncSaveAvailability())
    this.previewMap.on("idle", () => this.updateBackdrop())
    this.previewMap.once("load", () => {
      this.redrawOverlay()
      this.syncSaveAvailability()
    })
  }

  // Blurred ambient backdrop behind the poster frame: a snapshot of the
  // map canvas, refreshed whenever the map settles (idle covers pans,
  // zooms, restyles, and tile loads). Blob + object URL instead of a data
  // URL: async encode, no base64 strings, previous snapshot released
  // deterministically.
  updateBackdrop() {
    if (!this.hasBackdropTarget || !this.previewMap) return
    this.previewMap.getCanvas().toBlob(
      (blob) => {
        if (!blob || !this.hasBackdropTarget) return
        const previous = this.backdropUrl
        this.backdropUrl = URL.createObjectURL(blob)
        this.backdropTarget.src = this.backdropUrl
        this.backdropTarget.classList.remove("opacity-0")
        if (previous) URL.revokeObjectURL(previous)
      },
      "image/jpeg",
      0.5,
    )
  }

  releaseBackdrop() {
    if (!this.hasBackdropTarget) return
    this.backdropTarget.classList.add("opacity-0")
    this.backdropTarget.removeAttribute("src")
    if (this.backdropUrl) URL.revokeObjectURL(this.backdropUrl)
    this.backdropUrl = null
  }

  // ===== Live restyle =====

  posterStyle() {
    return buildPosterStyle({
      theme: this.resolvedTheme,
      trackGeojson: this.trackGeojson,
      extras: true,
      hiddenCategories: [...this.hidden],
      trackOpacity: this.trackOpacityValue(),
      trackWidth: this.trackWidthValue(),
    })
  }

  get resolvedTheme() {
    return resolveTheme(this.tokens)
  }

  scheduleRestyle() {
    clearTimeout(this.restyleTimer)
    this.restyleTimer = setTimeout(() => {
      this.previewMap?.setStyle(this.posterStyle())
      this.redrawOverlay()
    }, RESTYLE_DEBOUNCE_MS)
  }

  // ===== Theme =====

  initialThemeKey() {
    return this.swatchTargets[0]?.dataset.key || "blueprint"
  }

  async seedTheme(key) {
    const raw = await loadThemeTokens(key)
    this.tokens = { ...extendTokens(raw), ...raw }
    this.themeBase = key
    this.themeName =
      this.swatchTargets.find((el) => el.dataset.key === key)?.dataset.name ||
      raw.name ||
      key
    this.markSwatch(key)
    if (this.hasThemeLabelTarget)
      this.themeLabelTarget.textContent = this.themeName
    this.tokenTargets.forEach((input) => {
      const value = this.tokens[input.dataset.token]
      if (value) input.value = value
      this.syncTokenLabel(input)
    })
  }

  async pickTheme(event) {
    try {
      await this.seedTheme(event.currentTarget.dataset.key)
      this.scheduleRestyle()
      this.updateSummary()
    } catch (error) {
      Flash.show(
        "error",
        translate("poster.theme_load_failed", { error: error.message }),
      )
    }
  }

  tokenChanged(event) {
    this.tokens[event.target.dataset.token] = event.target.value
    this.syncTokenLabel(event.target)
    this.scheduleRestyle()
  }

  syncTokenLabel(input) {
    const label = this.tokenValueTargets.find(
      (el) => el.dataset.token === input.dataset.token,
    )
    if (label) label.textContent = input.value.toUpperCase()
  }

  markSwatch(key) {
    this.swatchTargets.forEach((swatch) => {
      swatch.classList.toggle("ring-2", swatch.dataset.key === key)
    })
  }

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
  }

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
  }

  get layout() {
    return layoutById(this.layoutSelectTarget.value)
  }

  layoutChanged() {
    this.resizeFrame()
    this.updateSummary()
    this.syncOrderAvailability()
    // Keep an open order view in sync with the new size: an orderable size
    // refreshes the dialog (and its price); a non-orderable one falls back to
    // the size picker. Skipped while an order is rendering/uploading so the
    // step list isn't reset mid-flight.
    if (this.orderViewOpen && !this.busy) this.openOrder()
  }

  get orderViewOpen() {
    if (!this.hasOrderDialogTarget) return false

    return (
      !this.orderDialogTarget.classList.contains("hidden") ||
      !this.sizePickerTarget.classList.contains("hidden")
    )
  }

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
  }

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
  }

  async loadFonts() {
    await Promise.allSettled(
      POSTER_FONTS.map((font) => ensurePosterFont(font.key, this.fontsValue)),
    )
  }

  get fontFamily() {
    return `"${fontByKey(this.fontSelectTarget.value).family}", sans-serif`
  }

  textChanged() {
    const enabled = this.textToggleTarget.checked
    ;[
      this.titleInputTarget,
      this.subtitleInputTarget,
      this.coordsToggleTarget,
      this.fontSelectTarget,
    ].forEach((el) => {
      el.disabled = !enabled
    })
    this.redrawOverlay()
  }

  async fontChanged() {
    await ensurePosterFont(this.fontSelectTarget.value, this.fontsValue)
    this.redrawOverlay()
  }

  posterText() {
    if (!this.textToggleTarget.checked)
      return { title: "", subtitle: "", coords: "" }
    return {
      title: this.titleInputTarget.value.trim(),
      subtitle: this.subtitleInputTarget.value.trim(),
      coords: this.coordsToggleTarget.checked
        ? formatCoords(this.previewMap?.getCenter())
        : "",
    }
  }

  dateRangeLabel() {
    const { startAt, endAt } = this.provider?.dateRange() ?? {}
    if (!startAt || !endAt) return ""
    const options = { day: "numeric", month: "short", year: "numeric" }
    const start = new Date(startAt)
    const end = new Date(endAt)
    return `${start.toLocaleDateString("en-GB", options)} – ${end.toLocaleDateString("en-GB", options)}`
  }

  // ===== Layers =====

  layersChanged() {
    this.hidden = new Set()
    this.element.querySelectorAll("[data-layer-category]").forEach((toggle) => {
      if (!toggle.checked) this.hidden.add(toggle.dataset.layerCategory)
    })
    this.trackOpacityLabelTarget.textContent = `${this.trackOpacityTarget.value}%`
    this.trackWidthLabelTarget.textContent = `${this.trackWidthTarget.value}%`
    this.scheduleRestyle()
  }

  trackOpacityValue() {
    return Number.parseInt(this.trackOpacityTarget.value, 10) / 100
  }

  trackWidthValue() {
    return Number.parseInt(this.trackWidthTarget.value, 10) / 100
  }

  // ===== Date range =====

  seedDateInputs() {
    if (!this.hasDateStartTarget || !this.hasDateEndTarget) return
    const { startAt, endAt } = this.provider.dateRange()
    if (!startAt) return
    this.dateStartTarget.value = toLocalInput(new Date(startAt))
    this.dateEndTarget.value = toLocalInput(new Date(endAt))
  }

  // SPA date change delegated to the provider — the studio never closes.
  async applyDates() {
    if (!this.provider?.supportsDateNavigation) return
    const start = this.dateStartTarget.value
    const end = this.dateEndTarget.value
    if (!start || !end) return

    const subtitleWasAuto =
      this.subtitleInputTarget.value === this.dateRangeLabel()
    this.setLoadBusy(true)
    this.setStatus(translate("poster.loading_tracks"))
    try {
      await this.provider.applyDates(start, end)

      if (subtitleWasAuto)
        this.subtitleInputTarget.value = this.dateRangeLabel()
      this.previewMap?.setStyle(this.posterStyle())
      this.recenter()
      this.syncSaveAvailability()
    } finally {
      this.setLoadBusy(false)
      this.setStatus("")
    }
  }

  setLoadBusy(value) {
    if (!this.hasLoadButtonTarget) return
    this.loadButtonTarget.disabled = value
    this.loadSpinnerTarget.classList.toggle("hidden", !value)
    this.loadLabelTarget.textContent = translate(
      value ? "poster.loading" : "poster.load",
    )
  }

  presetRange(event) {
    const now = new Date()
    const start = new Date(now)
    switch (event.currentTarget.dataset.range) {
      case "today":
        start.setHours(0, 0, 0, 0)
        break
      case "week":
        start.setDate(start.getDate() - 7)
        break
      case "month":
        start.setMonth(start.getMonth() - 1)
        break
    }
    this.dateStartTarget.value = toLocalInput(start)
    this.dateEndTarget.value = toLocalInput(now)
    this.applyDates()
  }

  // ===== Map interaction =====

  recenter() {
    const bounds =
      trackBounds(this.trackGeojson) ?? this.provider.fallbackBounds()
    if (bounds) this.previewMap?.fitBounds(bounds, { padding: 24 })
  }

  // ===== Preview overlay =====

  redrawOverlay() {
    if (!this.hasOverlayTarget) return
    const canvas = this.overlayTarget
    const dpr = window.devicePixelRatio || 1
    canvas.width = Math.round(this.frameTarget.clientWidth * dpr)
    canvas.height = Math.round(this.frameTarget.clientHeight * dpr)
    canvas.getContext("2d").clearRect(0, 0, canvas.width, canvas.height)
    drawOverlay(canvas, {
      theme: this.resolvedTheme,
      ...this.posterText(),
      font: this.fontFamily,
    })
  }

  // ===== Export =====

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
  }

  syncOrderAvailability() {
    // The "Order a print" zone is server-rendered only behind the
    // poster_ordering flag, and appears only when ordering is configured.
    if (!this.hasOrderSectionTarget) return

    this.orderSectionTarget.classList.toggle(
      "hidden",
      this.printOrderUrlValue.length === 0,
    )
  }

  // Exactly one of the three order views shows at a time, so the panel never
  // stacks the CTA, the size picker and the dialog on top of each other.
  showOrderView(which) {
    this.orderCtaTarget.classList.toggle("hidden", which !== "cta")
    this.sizePickerTarget.classList.toggle("hidden", which !== "picker")
    this.orderDialogTarget.classList.toggle("hidden", which !== "dialog")
  }

  openOrder() {
    const product = printProductFor(this.layout.id)
    if (product) this.showOrderDialog(product)
    else this.openSizePicker()
  }

  showOrderDialog(product) {
    this.orderSummaryTarget.textContent = translate("poster.order_summary", {
      layout: translate(`poster.layouts.${this.layout.id}`),
      price: product.priceLabel,
    })
    this.orderErrorTarget.classList.add("hidden")
    this.resetOrderSteps()
    this.showOrderView("dialog")
  }

  closeOrder() {
    this.showOrderView("cta")
  }

  openSizePicker() {
    this.showOrderView("picker")
  }

  closeSizePicker() {
    this.showOrderView("cta")
  }

  pickPrintSize(event) {
    const id = event.currentTarget.dataset.layoutId
    this.layoutSelectTarget.value = id
    // layoutChanged reopens the order view for the now-orderable size.
    this.layoutChanged()
  }

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
  }

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
  }

  resetOrderSteps() {
    this.orderStepsTarget.classList.add("hidden")
    this.orderActionsTarget.classList.remove("hidden")
  }

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
  }

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
  }

  // Server-side render through the sidecar: fills the hidden posters form
  // from the studio state and submits via Turbo. The sidecar renders its
  // classic 3:4 print poster around the studio's center; the result lands
  // in Recent posters via the gallery broadcast.
  saveToGallery() {
    if (!this.previewMap || this.saveButtonTarget.disabled) return
    const center = this.previewMap.getCenter()
    const distance = this.sidecarDistance()

    // The typed title is what gets drawn on the poster (blank ⇒ no title);
    // the gallery name is a separate required label that falls back to a
    // neutral placeholder so an untitled poster never reads "MY POSTER".
    const title = this.titleInputTarget.value.trim()
    this.saveTitleTarget.value = title
    this.saveNameTarget.value = title || translate("poster.untitled")
    this.saveThemeTarget.value = this.themeBase || "blueprint"
    this.saveLatTarget.value = center.lat
    this.saveLonTarget.value = center.lng
    this.saveDistanceTarget.value = distance
    const { startAt, endAt } = this.provider.dateRange()
    this.saveStartAtTarget.value = startAt || ""
    this.saveEndAtTarget.value = endAt || ""
    this.saveSourceTarget.value = this.provider.trackSource()
    this.saveOpacityTarget.value = this.trackOpacityTarget.value
    this.saveWidthTarget.value = this.trackWidthTarget.value
    this.saveFormTarget.requestSubmit()
    this.setStatus(translate("poster.queued"))
  }

  framedDistance() {
    const bounds = this.previewMap.getBounds()
    const heightMeters =
      (bounds.getNorth() - bounds.getSouth()) * METERS_PER_DEGREE
    return heightMeters * SIDECAR_DISTANCE_FACTOR
  }

  sidecarDistance() {
    const [min, max] = SIDECAR_DISTANCE_RANGE
    return Math.round(Math.min(max, Math.max(min, this.framedDistance())))
  }

  frameIsClamped() {
    const [, max] = SIDECAR_DISTANCE_RANGE
    return this.framedDistance() > max
  }

  // The server refuses renders without track data in the frame — mirror
  // both guards here so Save to gallery can't queue a doomed poster.
  syncSaveAvailability() {
    if (!this.hasSaveButtonTarget || !this.previewMap) return
    const coords = collectCoords(this.trackGeojson)
    let reason = null
    if (coords.length === 0) {
      reason = translate("poster.no_location_data")
    } else if (!this.frameCoversTrack(coords)) {
      reason = translate("poster.no_tracks_in_frame")
    }
    const message =
      reason ||
      (this.frameIsClamped() ? translate("poster.frame_too_wide") : null)
    this.saveButtonTarget.disabled = Boolean(reason)
    this.saveNoticeTarget.textContent = message || ""
    this.saveNoticeTarget.classList.toggle("hidden", !message)
  }

  // Mirrors the server's track_intersects_area?.
  frameCoversTrack(coords) {
    const center = this.previewMap.getCenter()

    return frameCovers(coords, center.lat, center.lng, this.sidecarDistance())
  }

  updateSummary() {
    const layout = this.layout
    const dpi = Number.parseInt(this.dpiTarget.value, 10)
    const geometry = resolveLayoutGeometry(layout, dpi)
    const lines = [
      `${translate(`poster.layouts.${layout.id}`)} — ${layout.dimensionsLabel}`,
      `Theme: ${this.themeName || "—"}`,
      `Export: ${geometry.width} × ${geometry.height}px${
        layout.kind === "paper" ? ` @ ${geometry.effectiveDpi} dpi` : ""
      }`,
    ]
    this.summaryTarget.textContent = lines.join(" · ")
  }

  // ===== Data plumbing =====

  get trackGeojson() {
    return (
      this.provider?.trackGeojson() ?? {
        type: "FeatureCollection",
        features: [],
      }
    )
  }

  setStatus(text) {
    this.statusTarget.textContent = text
  }

  setBusy(value) {
    this.busy = value
    this.downloadButtonTarget.disabled = value
  }
}
