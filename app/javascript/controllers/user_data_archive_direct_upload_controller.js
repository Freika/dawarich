import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"
import { showFlashMessage } from "../maps/helpers"

export default class extends Controller {
  static targets = ["input", "progress", "progressBar", "submit", "form"]
  static values = {
    url: String,
    userTrial: Boolean
  }

  connect() {
    this.inputTarget.addEventListener("change", this.upload.bind(this))

    // Add form submission handler to disable the file input
    if (this.hasFormTarget) {
      this.formTarget.addEventListener("submit", this.onSubmit.bind(this))
    }

    // Initially disable submit button if no files are uploaded
    if (this.hasSubmitTarget) {
      const hasUploadedFiles = this.element.querySelectorAll('input[name="archive"][type="hidden"]').length > 0
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
    // This ensures only our hidden input with signed ID is submitted
    this.inputTarget.disabled = true

    // Check if we have a signed ID
    const signedId = this.element.querySelector('input[name="archive"][type="hidden"]')
    if (!signedId) {
      event.preventDefault()
      console.log("No file uploaded yet")
      alert("Please select and upload a ZIP archive first")
    } else {
      console.log("Submitting form with uploaded archive")
    }
  }

  upload() {
    const files = this.inputTarget.files
    if (files.length === 0) return

    const file = files[0] // Only handle single file for archives

    // Validate file type
    if (!this.isValidZipFile(file)) {
      showFlashMessage('error', 'Please select a valid ZIP file.')
      this.inputTarget.value = ''
      return
    }

    // Check file size limits for trial users
    if (this.userTrialValue) {
      const MAX_FILE_SIZE = 11 * 1024 * 1024 // 11MB in bytes

      if (file.size > MAX_FILE_SIZE) {
        const message = `File size limit exceeded. Trial users can only upload files up to 10MB. File size: ${(file.size / 1024 / 1024).toFixed(1)}MB`
        showFlashMessage('error', message)

        // Clear the file input
        this.inputTarget.value = ''
        return
      }
    }

    console.log(`Uploading archive: ${file.name}`)
    this.isUploading = true

    // Disable submit button during upload
    this.submitTarget.disabled = true
    this.submitTarget.classList.add("opacity-50", "cursor-not-allowed")

    // Show uploading message using flash
    showFlashMessage('notice', `Uploading ${file.name}, please wait...`)

    // Always remove any existing progress bar to ensure we create a fresh one
    if (this.hasProgressTarget) {
      this.progressTarget.remove()
    }

    // Create a wrapper div with better DaisyUI styling
    const progressWrapper = document.createElement("div")
    progressWrapper.className = "w-full mt-4 mb-4"

    // Add a label with better typography
    const progressLabel = document.createElement("div")
    progressLabel.className = "text-sm font-medium text-base-content mb-2 flex justify-between items-center"
    progressLabel.innerHTML = `
      <span>Upload Progress</span>
      <span class="text-xs text-base-content/70 progress-percentage">0%</span>
    `
    progressWrapper.appendChild(progressLabel)

    // Create DaisyUI progress element
    const progressContainer = document.createElement("progress")
    progressContainer.setAttribute("data-user-data-archive-direct-upload-target", "progress")
    progressContainer.className = "progress progress-primary w-full h-3"
    progressContainer.value = 0
    progressContainer.max = 100

    // Create a hidden div for the progress bar target (for compatibility)
    const progressBarFill = document.createElement("div")
    progressBarFill.setAttribute("data-user-data-archive-direct-upload-target", "progressBar")
    progressBarFill.style.display = "none"

    progressWrapper.appendChild(progressContainer)
    progressWrapper.appendChild(progressBarFill)

    // Add the progress wrapper after the form-control div containing the file input
    const formControl = this.inputTarget.closest('.form-control')
    if (formControl) {
      formControl.parentNode.insertBefore(progressWrapper, formControl.nextSibling)
    } else {
      // Fallback: insert before submit button
      this.submitTarget.parentNode.insertBefore(progressWrapper, this.submitTarget)
    }

    console.log("Progress bar created and inserted after file input")

    // Clear any existing hidden field for archive
    const existingHiddenField = this.element.querySelector('input[name="archive"][type="hidden"]')
    if (existingHiddenField) {
      existingHiddenField.remove()
    }

    const upload = new DirectUpload(file, this.urlValue, this)
    upload.create((error, blob) => {
      if (error) {
        console.error("Error uploading file:", error)
        // Show error to user using flash
        showFlashMessage('error', `Error uploading ${file.name}: ${error.message || 'Unknown error'}`)

        // Re-enable submit button but keep it disabled since no file was uploaded
        this.submitTarget.disabled = true
        this.submitTarget.classList.add("opacity-50", "cursor-not-allowed")
      } else {
        console.log(`Successfully uploaded ${file.name} with ID: ${blob.signed_id}`)

        // Create a hidden field with the correct name
        const hiddenField = document.createElement("input")
        hiddenField.setAttribute("type", "hidden")
        hiddenField.setAttribute("name", "archive")
        hiddenField.setAttribute("value", blob.signed_id)
        this.element.appendChild(hiddenField)

        console.log("Added hidden field with signed ID:", blob.signed_id)

        // Enable submit button
        this.submitTarget.disabled = false
        this.submitTarget.classList.remove("opacity-50", "cursor-not-allowed")

        showFlashMessage('notice', `Archive uploaded successfully. Ready to import.`)

        // Add a completion animation to the progress bar
        const percentageDisplay = this.element.querySelector('.progress-percentage')
        if (percentageDisplay) {
          percentageDisplay.textContent = '100%'
          percentageDisplay.classList.add('text-success')
        }

        if (this.hasProgressTarget) {
          this.progressTarget.value = 100
          this.progressTarget.classList.add('progress-success')
          this.progressTarget.classList.remove('progress-primary')
        }
      }

      this.isUploading = false
      console.log("Upload completed")
    })
  }

  isValidZipFile(file) {
    // Check MIME type
    const validMimeTypes = ['application/zip', 'application/x-zip-compressed']
    if (validMimeTypes.includes(file.type)) {
      return true
    }

    // Check file extension as fallback
    const filename = file.name.toLowerCase()
    return filename.endsWith('.zip')
  }

  directUploadWillStoreFileWithXHR(request) {
    request.upload.addEventListener("progress", event => {
      if (!this.hasProgressTarget) {
        console.warn("Progress target not found")
        return
      }

      const progress = (event.loaded / event.total) * 100
      const progressPercentage = `${progress.toFixed(1)}%`
      console.log(`Upload progress: ${progressPercentage}`)

      // Update the DaisyUI progress element
      this.progressTarget.value = progress

      // Update the percentage display
      const percentageDisplay = this.element.querySelector('.progress-percentage')
      if (percentageDisplay) {
        percentageDisplay.textContent = progressPercentage
      }
    })
  }
}