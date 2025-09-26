import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"
import { showFlashMessage } from "../maps/helpers"

export default class extends Controller {
  static targets = ["input", "progress", "progressBar", "submit", "form"]
  static values = {
    url: String,
    userTrial: Boolean,
    currentImportsCount: Number
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

    // Check import count limits for trial users
    if (this.userTrialValue && this.currentImportsCountValue >= 5) {
      const message = 'Import limit reached. Trial users can only create up to 5 imports. Please subscribe to import more files.'
      showFlashMessage('error', message)

      // Clear the file input
      this.inputTarget.value = ''
      return
    }

    // Check file size limits for trial users
    if (this.userTrialValue) {
      const MAX_FILE_SIZE = 11 * 1024 * 1024 // 11MB in bytes
      const oversizedFiles = Array.from(files).filter(file => file.size > MAX_FILE_SIZE)

      if (oversizedFiles.length > 0) {
        const fileNames = oversizedFiles.map(f => f.name).join(', ')
        const message = `File size limit exceeded. Trial users can only upload files up to 10MB. Oversized files: ${fileNames}`
        showFlashMessage('error', message)

        // Clear the file input
        this.inputTarget.value = ''
        return
      }
    }

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
    progressContainer.setAttribute("data-direct-upload-target", "progress")
    progressContainer.className = "progress progress-primary w-full h-3"
    progressContainer.value = 0
    progressContainer.max = 100

    // Create a hidden div for the progress bar target (for compatibility)
    const progressBarFill = document.createElement("div")
    progressBarFill.setAttribute("data-direct-upload-target", "progressBar")
    progressBarFill.style.display = "none"

    progressWrapper.appendChild(progressContainer)
    progressWrapper.appendChild(progressBarFill)

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
          console.log("All uploads completed")
          console.log(`Ready to submit with ${successfulUploads} files`)
        }
      })
    })
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
