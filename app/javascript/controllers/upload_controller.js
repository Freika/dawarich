import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"
import Flash from "./flash_controller"

const MAX_FILE_SIZE = 11 * 1024 * 1024 // 11MB
const VALID_ZIP_TYPES = ["application/zip", "application/x-zip-compressed"]

export default class extends Controller {
  static targets = ["input", "progress", "progressBar", "submit", "form"]
  static values = {
    url: String,
    fieldName: { type: String, default: "import[files][]" },
    multiple: { type: Boolean, default: true },
    validateZip: { type: Boolean, default: false },
    userTrial: { type: Boolean, default: false },
    maxImports: { type: Number, default: 0 },
    currentImportsCount: { type: Number, default: 0 },
  }

  connect() {
    this.isUploading = false
    this.inputTarget.addEventListener("change", this.upload.bind(this))
    if (this.hasFormTarget) {
      this.formTarget.addEventListener("submit", this.onSubmit.bind(this))
    }
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = !this.hasUploadedFiles()
    }
  }

  onSubmit(event) {
    if (this.isUploading) {
      event.preventDefault()
      return
    }
    this.inputTarget.disabled = true
    if (!this.hasUploadedFiles()) {
      event.preventDefault()
      Flash.show("error", "Please select and upload files first")
    }
  }

  upload() {
    const files = Array.from(this.inputTarget.files)
    if (files.length === 0) return

    const filesToUpload = this.multipleValue ? files : [files[0]]

    if (!this.validateFiles(filesToUpload)) return

    this.isUploading = true
    this.disableSubmit()
    Flash.show(
      "notice",
      `Uploading ${filesToUpload.length} file(s), please wait...`,
    )
    this.createProgressBar()
    this.clearExistingHiddenFields()

    let completed = 0
    filesToUpload.forEach((file) => {
      const upload = new DirectUpload(file, this.urlValue, this)
      upload.create((error, blob) => {
        completed++
        if (error) {
          Flash.show(
            "error",
            `Error uploading ${file.name}: ${error.message || "Unknown error"}`,
          )
        } else {
          this.addHiddenField(blob.signed_id)
        }
        if (completed === filesToUpload.length) this.uploadComplete()
      })
    })
  }

  validateFiles(files) {
    if (
      this.userTrialValue &&
      this.maxImportsValue > 0 &&
      this.currentImportsCountValue >= this.maxImportsValue
    ) {
      Flash.show(
        "error",
        `Import limit reached. Trial users can only create up to ${this.maxImportsValue} imports.`,
      )
      this.inputTarget.value = ""
      return false
    }

    if (this.validateZipValue) {
      const file = files[0]
      if (
        !VALID_ZIP_TYPES.includes(file.type) &&
        !file.name.toLowerCase().endsWith(".zip")
      ) {
        Flash.show("error", "Please select a valid ZIP file.")
        this.inputTarget.value = ""
        return false
      }
    }

    if (this.userTrialValue) {
      const oversized = files.filter((f) => f.size > MAX_FILE_SIZE)
      if (oversized.length > 0) {
        Flash.show(
          "error",
          `File size limit exceeded. Trial users can only upload files up to 10MB.`,
        )
        this.inputTarget.value = ""
        return false
      }
    }

    return true
  }

  createProgressBar() {
    if (this.hasProgressTarget) this.progressTarget.remove()

    const wrapper = document.createElement("div")
    wrapper.className = "w-full mt-4 mb-4"
    wrapper.innerHTML = `
      <div class="text-sm font-medium text-base-content mb-2 flex justify-between items-center">
        <span>Upload Progress</span>
        <span class="text-xs text-base-content/70 progress-percentage">0%</span>
      </div>
      <progress data-upload-target="progress" class="progress progress-primary w-full h-3" value="0" max="100"></progress>
      <div data-upload-target="progressBar" style="display:none"></div>
    `
    this.submitTarget.parentNode.insertBefore(wrapper, this.submitTarget)
  }

  uploadComplete() {
    const count = this.hiddenFieldCount()
    this.submitTarget.disabled = count === 0
    this.submitTarget.classList.toggle("opacity-50", count === 0)
    this.submitTarget.classList.toggle("cursor-not-allowed", count === 0)

    if (count === 0) {
      Flash.show(
        "error",
        "No files were successfully uploaded. Please try again.",
      )
    } else {
      Flash.show(
        "notice",
        `${count} file(s) uploaded successfully. Ready to submit.`,
      )
      this.markProgressComplete()
    }
    this.isUploading = false
  }

  markProgressComplete() {
    const pct = this.element.querySelector(".progress-percentage")
    if (pct) {
      pct.textContent = "100%"
      pct.classList.add("text-success")
    }
    if (this.hasProgressTarget) {
      this.progressTarget.value = 100
      this.progressTarget.classList.add("progress-success")
      this.progressTarget.classList.remove("progress-primary")
    }
  }

  directUploadWillStoreFileWithXHR(request) {
    request.upload.addEventListener("progress", (event) => {
      if (!this.hasProgressTarget) return
      const progress = (event.loaded / event.total) * 100
      this.progressTarget.value = progress
      const pct = this.element.querySelector(".progress-percentage")
      if (pct) pct.textContent = `${progress.toFixed(1)}%`
    })
  }

  addHiddenField(signedId) {
    const field = document.createElement("input")
    field.type = "hidden"
    field.name = this.fieldNameValue
    field.value = signedId
    this.element.appendChild(field)
  }

  clearExistingHiddenFields() {
    this.element
      .querySelectorAll(`input[name="${this.fieldNameValue}"][type="hidden"]`)
      .forEach((el) => {
        el.remove()
      })
  }

  hasUploadedFiles() {
    return this.hiddenFieldCount() > 0
  }

  hiddenFieldCount() {
    return this.element.querySelectorAll(
      `input[name="${this.fieldNameValue}"][type="hidden"]`,
    ).length
  }

  disableSubmit() {
    this.submitTarget.disabled = true
    this.submitTarget.classList.add("opacity-50", "cursor-not-allowed")
  }
}
