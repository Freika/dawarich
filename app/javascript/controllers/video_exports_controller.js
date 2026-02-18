import consumer from "../channels/consumer"
import BaseController from "./base_controller"

const STATUS_BADGES = {
  created: '<span class="badge badge-info">Created</span>',
  processing: '<span class="badge badge-warning">Processing</span>',
  completed: '<span class="badge badge-success">Completed</span>',
  failed: '<span class="badge badge-error">Failed</span>',
}

export default class extends BaseController {
  static targets = ["table", "modal", "modalTitle", "videoPlayer"]

  connect() {
    if (!this.hasTableTarget) return

    this.channel = consumer.subscriptions.create(
      { channel: "VideoExportsChannel" },
      {
        received: (data) => this._handleUpdate(data),
      },
    )

    if (this.hasModalTarget) {
      this.modalTarget.addEventListener("close", () => this._stopVideo())
    }
  }

  disconnect() {
    if (this.channel) {
      this.channel.unsubscribe()
    }
  }

  preview(event) {
    event.preventDefault()
    const { videoUrl, videoName } = event.currentTarget.dataset

    this.videoPlayerTarget.src = videoUrl
    this.modalTitleTarget.textContent = videoName || "Video Preview"
    this.modalTarget.showModal()
  }

  _stopVideo() {
    this.videoPlayerTarget.pause()
    this.videoPlayerTarget.removeAttribute("src")
    this.videoPlayerTarget.load()
  }

  _handleUpdate(data) {
    const row = this.element.querySelector(
      `tr[data-video-export-id="${data.id}"]`,
    )
    if (!row) return

    const statusCell = row.querySelector("[data-status]")
    if (statusCell) {
      statusCell.innerHTML = STATUS_BADGES[data.status] || data.status
      if (data.status === "failed" && data.error_message) {
        const badge = statusCell.querySelector(".badge")
        if (badge) badge.title = data.error_message
      }
    }

    const actionsCell = row.querySelector("[data-actions]")
    if (actionsCell) {
      this._updateActions(actionsCell, data)
    }
  }

  _updateActions(cell, data) {
    const existingDownload = cell.querySelector("[data-download-link]")

    if (data.status === "completed" && data.download_url) {
      const deleteBtn = cell.querySelector("[data-delete-link]")

      if (!cell.querySelector("[data-preview-link]") && data.preview_url) {
        const previewBtn = document.createElement("button")
        previewBtn.type = "button"
        previewBtn.className = "px-4 py-2 bg-purple-500 text-white rounded-md"
        previewBtn.dataset.action = "click->video-exports#preview"
        previewBtn.dataset.videoUrl = data.preview_url
        previewBtn.dataset.videoName = data.name
        previewBtn.dataset.previewLink = ""
        previewBtn.textContent = "Preview"
        if (deleteBtn) {
          cell.insertBefore(previewBtn, deleteBtn)
        } else {
          cell.appendChild(previewBtn)
        }
      }

      if (!existingDownload) {
        const link = document.createElement("a")
        link.href = data.download_url
        link.className = "px-4 py-2 bg-blue-500 text-white rounded-md"
        link.dataset.downloadLink = ""
        link.textContent = "Download"
        link.download = ""
        if (deleteBtn) {
          cell.insertBefore(link, deleteBtn)
        } else {
          cell.appendChild(link)
        }
      }
    }
  }
}
