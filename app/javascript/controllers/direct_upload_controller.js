import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

export default class extends Controller {
  static targets = ["input", "progress", "submit"]
  static values = {
    url: String
  }

  connect() {
    this.inputTarget.addEventListener("change", this.upload.bind(this))
  }

  upload() {
    const files = this.inputTarget.files
    if (files.length === 0) return

    // Disable submit button during upload
    this.submitTarget.disabled = true

    // Create progress bar if it doesn't exist
    if (!this.hasProgressTarget) {
      const progressBar = document.createElement("div")
      progressBar.setAttribute("data-direct-upload-target", "progress")
      progressBar.className = "w-full bg-gray-200 rounded-full h-2.5 mt-2"
      this.inputTarget.parentNode.appendChild(progressBar)
    }

    Array.from(files).forEach(file => {
      const upload = new DirectUpload(file, this.urlValue, this)
      upload.create((error, blob) => {
        if (error) {
          console.error("Error uploading file:", error)
        } else {
          const hiddenField = document.createElement("input")
          hiddenField.setAttribute("type", "hidden")
          hiddenField.setAttribute("name", this.inputTarget.name)
          hiddenField.setAttribute("value", blob.signed_id)
          this.element.appendChild(hiddenField)
        }
      })
    })
  }

  directUploadWillStoreFileWithXHR(request) {
    request.upload.addEventListener("progress", event => {
      const progress = (event.loaded / event.total) * 100
      this.progressTarget.style.width = `${progress}%`
    })
  }

  directUploadDidProgress(event) {
    // This method is called by ActiveStorage during the upload
    // We're handling progress in directUploadWillStoreFileWithXHR instead
  }
}
