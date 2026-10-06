import { MapPageProvider } from "poster_studio/data/providers"
import { ensureHudFonts } from "video_studio/hud_fonts"
import { defaultSettings } from "video_studio/studio_state"
import { translate } from "i18n"
import Flash from "controllers/flash_controller"
import { bindControls, controls } from "./video_studio_controls.js"
import { dates } from "./video_studio_dates.js"
import { preview } from "./video_studio_preview.js"
import { rendering } from "./video_studio_render.js"
import { saving } from "./video_studio_save.js"

const instances = new WeakMap()
const targets =
  "stage frame preview overlay result status progressBar renderButton saveButton cancelButton nameInput themeSwatch themeLabel durationLabel trackWidthLabel fogOpacityLabel fogColorLabel trackColorLabel fogControls visualizationMode formatOption hudScaleLabel formatDims dateStart dateEnd rangeControls rangeDisplay loadButton loadSpinner switchButton rangeLabel summary".split(
    " ",
  )

const lifecycle = {
  async open(provider = null) {
    if (!this.element.classList.contains("hidden")) return
    const operation = this.startOperation()
    this.provider =
      provider ?? new MapPageProvider({ application: this.application })
    this.element.classList.remove("hidden")
    this.syncDateTimeControls()
    this.setRangeBusy(true)

    try {
      await this.reloadTrack(operation)
      if (!this.operationIsCurrent(operation)) return
      if (!this.nameInputTarget.value) {
        this.nameInputTarget.value =
          this.provider.defaultTitle() || this.dateRangeLabel()
      }
      const families = await ensureHudFonts(this.fontsValue)
      if (!this.operationIsCurrent(operation)) return
      this.families = families
      await this.refreshStyle(operation)
      if (!this.operationIsCurrent(operation)) return
      this.renderStats()
      this.syncSupport()
    } catch (error) {
      if (this.operationIsCurrent(operation)) {
        Flash.show(
          "error",
          translate("video.open_failed", { error: error.message }),
        )
      }
    } finally {
      if (this.operationIsCurrent(operation)) this.setRangeBusy(false)
    }
  },
  close() {
    this.invalidateOperation()
    this.cancel()
    this.saveAbortController?.abort()
    this.teardown()
    this.setRangeBusy(false)
    this.element.classList.add("hidden")
  },
  switchToPoster() {
    if (this.rendering || this.rangeLoading) return
    const provider = this.provider
    this.close()
    document.dispatchEvent(
      new CustomEvent("poster-studio:open", { detail: { provider } }),
    )
  },
  startOperation() {
    this.operationVersion = (this.operationVersion || 0) + 1
    return this.operationVersion
  },
  invalidateOperation() {
    this.operationVersion = (this.operationVersion || 0) + 1
  },
  operationIsCurrent(operation) {
    return !this.disposed && operation === this.operationVersion
  },
}

export function mountVideoStudio(element, application = window.Stimulus) {
  if (instances.has(element)) {
    const studio = instances.get(element)
    if (application) studio.application = application
    return studio
  }
  const studio = Object.assign(
    {
      element,
      application,
      operationVersion: 0,
      disposed: false,
      settings: defaultSettings(),
      fontsValue: JSON.parse(element.dataset.videoStudioFontsValue || "{}"),
      uploadUrlValue: element.dataset.videoStudioUploadUrlValue,
      createUrlValue: element.dataset.videoStudioCreateUrlValue,
    },
    controls,
    dates,
    preview,
    rendering,
    saving,
    lifecycle,
  )
  for (const name of targets) {
    const selector = `[data-video-studio-target~="${name}"]`
    Object.defineProperties(studio, {
      [`${name}Target`]: { get: () => element.querySelector(selector) },
      [`${name}Targets`]: {
        get: () => [...element.querySelectorAll(selector)],
      },
      [`has${name[0].toUpperCase()}${name.slice(1)}Target`]: {
        get: () => element.querySelector(selector) !== null,
      },
    })
  }
  studio.unbind = bindControls(studio)
  instances.set(element, studio)
  studio.syncControls()
  return studio
}

export function destroyVideoStudio(element) {
  const studio = instances.get(element)
  if (!studio) return
  studio.disposed = true
  studio.close()
  studio.saveAbortController?.abort()
  studio.unbind()
  instances.delete(element)
}

export const VideoStudio = {
  mounted() {
    this.studio = mountVideoStudio(this.el)
  },
  reconnected() {
    this.studio?.syncSupport()
  },
  destroyed() {
    destroyVideoStudio(this.el)
  },
}
