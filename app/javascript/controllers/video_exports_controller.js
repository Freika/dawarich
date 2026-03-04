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

    if (row) {
      this._updateRow(row, data)
    } else {
      this._insertNewRow(data)
    }
  }

  _updateRow(row, data) {
    const statusCell = row.querySelector("[data-status]")
    if (statusCell) {
      if (STATUS_BADGES[data.status]) {
        statusCell.innerHTML = STATUS_BADGES[data.status]
      } else {
        statusCell.textContent = data.status
      }
      if (data.status === "failed" && data.error_message) {
        const badge = statusCell.querySelector(".badge")
        if (badge) badge.title = data.error_message
      }
    }

    const fileSizeCell = row.querySelector("[data-file-size]")
    if (fileSizeCell && data.file_size) {
      fileSizeCell.textContent = data.file_size
    }

    const actionsCell = row.querySelector("[data-actions]")
    if (actionsCell) {
      this._updateActions(actionsCell, data)
    }
  }

  _insertNewRow(data) {
    if (!this.hasTableTarget) {
      this._replaceEmptyState()
    }

    if (!this.hasTableTarget) return

    const tbody = this.tableTarget.querySelector("tbody")
    if (!tbody) return

    const row = document.createElement("tr")
    row.dataset.videoExportId = data.id

    const nameCell = document.createElement("td")
    nameCell.textContent = data.name || ""
    row.appendChild(nameCell)

    const sizeCell = document.createElement("td")
    sizeCell.dataset.fileSize = ""
    sizeCell.textContent = data.file_size || "N/A"
    row.appendChild(sizeCell)

    const dateCell = document.createElement("td")
    dateCell.textContent = data.created_at || ""
    row.appendChild(dateCell)

    const statusCell = document.createElement("td")
    statusCell.dataset.status = ""
    statusCell.innerHTML = STATUS_BADGES[data.status] || data.status
    row.appendChild(statusCell)

    const actionsCell = document.createElement("td")
    actionsCell.className = "whitespace-nowrap flex items-center gap-2"
    actionsCell.dataset.actions = ""
    this._buildActions(actionsCell, data)
    row.appendChild(actionsCell)

    tbody.prepend(row)
  }

  _replaceEmptyState() {
    const container = this.element.querySelector("#video_exports")
    if (!container) return

    container.innerHTML = `
      <div class="overflow-x-auto">
        <table class="table overflow-x-auto" data-video-exports-target="table">
          <thead>
            <tr>
              <th>Name</th>
              <th>File size</th>
              <th>Created at</th>
              <th>Status</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody></tbody>
        </table>
      </div>
    `
  }

  _buildActions(cell, data) {
    if (data.status === "completed" && data.download_url) {
      if (data.preview_url) {
        const previewBtn = document.createElement("button")
        previewBtn.type = "button"
        previewBtn.className = "px-4 py-2 bg-purple-500 text-white rounded-md"
        previewBtn.dataset.action = "click->video-exports#preview"
        previewBtn.dataset.videoUrl = data.preview_url
        previewBtn.dataset.videoName = data.name
        previewBtn.dataset.previewLink = ""
        previewBtn.textContent = "Preview"
        cell.appendChild(previewBtn)
      }

      const downloadLink = document.createElement("a")
      downloadLink.href = data.download_url
      downloadLink.className = "px-4 py-2 bg-blue-500 text-white rounded-md"
      downloadLink.dataset.downloadLink = ""
      downloadLink.textContent = "Download"
      downloadLink.download = ""
      cell.appendChild(downloadLink)
    }

    if (data.delete_url) {
      const deleteLink = document.createElement("a")
      deleteLink.href = data.delete_url
      deleteLink.className = "px-4 py-2 bg-red-500 text-white rounded-md"
      deleteLink.dataset.turboMethod = "delete"
      deleteLink.dataset.turboConfirm = "Are you sure?"
      deleteLink.dataset.deleteLink = ""
      deleteLink.textContent = "Delete"
      cell.appendChild(deleteLink)
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
