import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"
import { showFlashMessage } from "../maps/helpers"

export default class extends Controller {
  static targets = ["input", "progress", "progressBar", "submit", "form"]
  static values = {
    url: String
  }

  connect() {
    this.inputTarget.addEventListener("change", this.upload.bind(this))

    // Add form submission handler to disable the file input
    if (this.hasFormTarget) {
      this.formTarget.addEventListener("submit", this.onSubmit.bind(this))
    }

    // Initially disable submit button if no files are uploaded
    if (this.hasSubmitTarget) {
      const hasUploadedFiles = this.element.querySelectorAll('input[name="import[files][]"][type="hidden"]').length > 0
      this.submitTarget.disabled = !hasUploadedFiles
    }
  }

  onSubmit(event) {
    if (this.isUploading) {
      // If still uploading, prevent submission
      event.preventDefault()
      console.log("Form submission prevented during upload")
      return
    }

    // Disable the file input to prevent it from being submitted with the form
    // This ensures only our hidden inputs with signed IDs are submitted
    this.inputTarget.disabled = true

    // Check if we have any signed IDs
    const signedIds = this.element.querySelectorAll('input[name="import[files][]"][type="hidden"]')
    if (signedIds.length === 0) {
      event.preventDefault()
      console.log("No files uploaded yet")
      alert("Please select and upload files first")
    } else {
      console.log(`Submitting form with ${signedIds.length} uploaded files`)
    }
  }

  upload() {
    const files = this.inputTarget.files
    if (files.length === 0) return

    console.log(`Uploading ${files.length} files`)
    this.isUploading = true

    // Disable submit button during upload
    this.submitTarget.disabled = true
    this.submitTarget.classList.add("opacity-50", "cursor-not-allowed")

    // Show uploading message using flash
    showFlashMessage('notice', `Uploading ${files.length} files, please wait...`)

    // Always remove any existing progress bar to ensure we create a fresh one
    if (this.hasProgressTarget) {
      this.progressTarget.remove()
    }

    // Create a wrapper div for better positioning and visibility
    const progressWrapper = document.createElement("div")
    progressWrapper.className = "mt-4 mb-6 border p-4 rounded-lg bg-gray-50"

    // Add a label
    const progressLabel = document.createElement("div")
    progressLabel.className = "font-medium mb-2 text-gray-700"
    progressLabel.textContent = "Upload Progress"
    progressWrapper.appendChild(progressLabel)

    // Create a new progress container
    const progressContainer = document.createElement("div")
    progressContainer.setAttribute("data-direct-upload-target", "progress")
    progressContainer.className = "w-full bg-gray-200 rounded-full h-4"

    // Create the progress bar fill element
    const progressBarFill = document.createElement("div")
    progressBarFill.setAttribute("data-direct-upload-target", "progressBar")
    progressBarFill.className = "bg-blue-600 h-4 rounded-full transition-all duration-300"
    progressBarFill.style.width = "0%"

    // Add the fill element to the container
    progressContainer.appendChild(progressBarFill)
    progressWrapper.appendChild(progressContainer)
    progressBarFill.dataset.percentageDisplay = "true"

    // Add the progress wrapper AFTER the file input field but BEFORE the submit button
    this.submitTarget.parentNode.insertBefore(progressWrapper, this.submitTarget)

    console.log("Progress bar created and inserted before submit button")

    let uploadCount = 0
    const totalFiles = files.length

    // Clear any existing hidden fields for files
    this.element.querySelectorAll('input[name="import[files][]"][type="hidden"]').forEach(el => {
      if (el !== this.inputTarget) {
        el.remove()
      }
    });

    Array.from(files).forEach(file => {
      console.log(`Starting upload for ${file.name}`)
      const upload = new DirectUpload(file, this.urlValue, this)
      upload.create((error, blob) => {
        uploadCount++

        if (error) {
          console.error("Error uploading file:", error)
          // Show error to user using flash
          showFlashMessage('error', `Error uploading ${file.name}: ${error.message || 'Unknown error'}`)
        } else {
          console.log(`Successfully uploaded ${file.name} with ID: ${blob.signed_id}`)

          // Create a hidden field with the correct name
          const hiddenField = document.createElement("input")
          hiddenField.setAttribute("type", "hidden")
          hiddenField.setAttribute("name", "import[files][]")
          hiddenField.setAttribute("value", blob.signed_id)
          this.element.appendChild(hiddenField)

          console.log("Added hidden field with signed ID:", blob.signed_id)
        }

        // Enable submit button when all uploads are complete
        if (uploadCount === totalFiles) {
          // Only enable submit if we have at least one successful upload
          const successfulUploads = this.element.querySelectorAll('input[name="import[files][]"][type="hidden"]').length
          this.submitTarget.disabled = successfulUploads === 0
          this.submitTarget.classList.toggle("opacity-50", successfulUploads === 0)
          this.submitTarget.classList.toggle("cursor-not-allowed", successfulUploads === 0)

          if (successfulUploads === 0) {
            showFlashMessage('error', 'No files were successfully uploaded. Please try again.')
          } else {
            showFlashMessage('notice', `${successfulUploads} file(s) uploaded successfully. Ready to submit.`)
          }
          this.isUploading = false
          console.log("All uploads completed")
          console.log(`Ready to submit with ${successfulUploads} files`)
        }
      })
    })
  }

    directUploadWillStoreFileWithXHR(request) {
    request.upload.addEventListener("progress", event => {
      if (!this.hasProgressBarTarget) {
        console.warn("Progress bar target not found")
        return
      }

      const progress = (event.loaded / event.total) * 100
      const progressPercentage = `${progress.toFixed(1)}%`
      console.log(`Upload progress: ${progressPercentage}`)
      this.progressBarTarget.style.width = progressPercentage

      // Update text percentage if exists
      const percentageDisplay = this.element.querySelector('[data-percentage-display="true"]')
      if (percentageDisplay) {
        percentageDisplay.textContent = progressPercentage
      }
    })
  }
}
