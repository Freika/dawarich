import { translate } from "i18n"
import Flash from "controllers/flash_controller"
import { saveVideo } from "video_studio/save_video"
import { provenanceOf } from "video_studio/studio_state"

export const saving = {
  async save() {
    if (!this.blob || this.rangeLoading || this.saving) return
    const operation = this.operationVersion
    const controller = new AbortController()
    this.saveAbortController = controller
    this.saving = true
    this.saveButtonTarget.disabled = true
    try {
      const stream = await saveVideo({
        blob: this.blob,
        name: this.nameInputTarget.value,
        settings: { ...this.settings, ...provenanceOf(this.provider) },
        uploadUrl: this.uploadUrlValue,
        createUrl: this.createUrlValue,
        signal: controller.signal,
        onProgress: (ratio) => {
          if (this.operationIsCurrent(operation))
            this.showProgress(ratio, "uploading")
        },
      })
      if (!this.operationIsCurrent(operation)) return
      window.Turbo.renderStreamMessage(stream)
      this.showProgress(0, null)
    } catch (error) {
      if (this.operationIsCurrent(operation) && error.name !== "AbortError") {
        Flash.show(
          "error",
          translate("video.save_failed", { error: error.message }),
        )
      }
    } finally {
      this.saving = false
      if (this.saveAbortController === controller)
        this.saveAbortController = null
      if (this.operationIsCurrent(operation))
        this.saveButtonTarget.disabled = !this.blob
    }
  },
}
