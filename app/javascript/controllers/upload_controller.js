import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"
import { shouldZip, zipSingleFile } from "services/zip_file"
import Flash from "./flash_controller"

const MAX_FILE_SIZE = 11 * 1024 * 1024 // 11MB
const VALID_ZIP_TYPES = ["application/zip", "application/x-zip-compressed"]

const ACCEPTED_EXTENSIONS = [
  "json",
  "geojson",
  "gpx",
  "kml",
  "kmz",
  "tcx",
  "fit",
  "csv",
  "rec",
  "zip",
]

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
    this.fileProgress = {}
    this.totalBytes = 0
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

  async upload() {
    const files = Array.from(this.inputTarget.files)
    if (files.length === 0) return

    const filesToUpload = this.multipleValue ? files : [files[0]]

    if (!this.validateFiles(filesToUpload)) return

    this.isUploading = true
    this.disableSubmit()
    this.createProgressBar()
    this.clearExistingHiddenFields()

    const willCompress = filesToUpload.some((f) => shouldZip(f))
    Flash.show(
      "notice",
      willCompress
        ? `Preparing ${filesToUpload.length} file(s) for upload...`
        : `Uploading ${filesToUpload.length} file(s), please wait...`,
    )

    const prepared = await this.prepareForUpload(filesToUpload)

    this.totalBytes = prepared.reduce((sum, f) => sum + f.size, 0)
    this.fileProgress = {}

    let completed = 0
    prepared.forEach((file, index) => {
      this.fileProgress[index] = 0
      const upload = new DirectUpload(file, this.urlValue, {
        directUploadWillStoreFileWithXHR: (request) => {
          request.upload.addEventListener("progress", (event) => {
            this.fileProgress[index] = event.loaded
            this.updateAggregateProgress()
          })
        },
      })
      upload.create((error, blob) => {
        completed++
        if (error) {
          Flash.show(
            "error",
            `Error uploading ${file.name}: ${error.message || "Unknown error"}`,
          )
        } else {
          this.fileProgress[index] = file.size
          this.addHiddenField(blob.signed_id)
        }
        if (completed === prepared.length) this.uploadComplete()
      })
    })
  }

  async prepareForUpload(files) {
    const result = []
    for (const original of files) {
      if (!shouldZip(original)) {
        result.push(original)
        continue
      }
      try {
        const zipped = await zipSingleFile(original)
        result.push(zipped)
      } catch (err) {
        console.error(
          "Client-side zip failed, uploading raw:",
          original.name,
          err,
        )
        Flash.show(
          "warning",
          `Could not compress ${original.name}, uploading as-is.`,
        )
        result.push(original)
      }
    }
    return result
  }

  validateFiles(files) {
    const unsupported = files.filter((f) => !this.hasAcceptedExtension(f))
    if (unsupported.length > 0) {
      const names = unsupported.map((f) => f.name).join(", ")
      const accepted = ACCEPTED_EXTENSIONS.map((e) => `.${e}`).join(", ")
      Flash.show(
        "error",
        `Unsupported file type: ${names}. Supported formats: ${accepted}.`,
      )
      this.inputTarget.value = ""
      return false
    }

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

  updateAggregateProgress() {
    if (!this.hasProgressTarget) return
    const loaded = Object.values(this.fileProgress).reduce((a, b) => a + b, 0)
    const percent = this.totalBytes > 0 ? (loaded / this.totalBytes) * 100 : 0
    this.progressTarget.value = percent
    const pct = this.element.querySelector(".progress-percentage")
    if (pct) pct.textContent = `${percent.toFixed(1)}%`
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

  hasAcceptedExtension(file) {
    const dot = file.name.lastIndexOf(".")
    if (dot < 0 || dot === file.name.length - 1) return false
    const ext = file.name.slice(dot + 1).toLowerCase()
    return ACCEPTED_EXTENSIONS.includes(ext)
  }
}
