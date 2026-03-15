import consumer from "../channels/consumer"
import BaseController from "./base_controller"
import Flash from "./flash_controller"

const STATUS_CONFIG = {
  created: { label: "Created", className: "badge badge-info" },
  processing: { label: "Processing", className: "badge badge-warning" },
  completed: { label: "Completed", className: "badge badge-success" },
  failed: { label: "Failed", className: "badge badge-error" },
}

function createStatusBadge(status) {
  const config = STATUS_CONFIG[status]
  const span = document.createElement("span")
  if (config) {
    span.className = config.className
    span.textContent = config.label
  } else {
    span.textContent = status
  }
  return span
}

export default class extends BaseController {
  static targets = ["table", "modal", "modalTitle", "videoPlayer"]
  static values = { apiKey: String }

  connect() {
    this.channel = consumer.subscriptions.create(
      { channel: "VideoExportsChannel" },
      {
        received: (data) => this._handleUpdate(data),
      },
    )

    this._boundCloseHandler = () => this._stopVideo()
    if (this.hasModalTarget) {
      this.modalTarget.addEventListener("close", this._boundCloseHandler)
    }
  }

  disconnect() {
    if (this.channel) {
      this.channel.unsubscribe()
      this.channel = null
    }

    if (this._boundCloseHandler && this.hasModalTarget) {
      this.modalTarget.removeEventListener("close", this._boundCloseHandler)
      this._boundCloseHandler = null
    }
  }

  async retry(event) {
    const btn = event.currentTarget
    const config = JSON.parse(btn.dataset.retryConfig || "{}")
    const trackId = btn.dataset.retryTrackId || null
    const startAt = btn.dataset.retryStartAt || null
    const endAt = btn.dataset.retryEndAt || null

    btn.disabled = true
    btn.textContent = "Retrying..."

    try {
      const response = await fetch("/api/v1/video_exports", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${this.apiKeyValue}`,
        },
        body: JSON.stringify({
          track_id: trackId ? Number.parseInt(trackId, 10) : null,
          start_at: startAt,
          end_at: endAt,
          config,
        }),
      })

      if (response.ok) {
        Flash.show("success", "Video export retry started!")
      } else {
        let message = "Failed to retry video export"
        try {
          const data = await response.json()
          message = data.errors?.join(", ") || message
        } catch {
          // Non-JSON error response
        }
        Flash.show("error", message)
      }
    } catch (error) {
      Flash.show("error", `Error: ${error.message}`)
    } finally {
      btn.disabled = false
      btn.textContent = "Retry"
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
      statusCell.textContent = ""
      statusCell.appendChild(createStatusBadge(data.status))

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
    statusCell.appendChild(createStatusBadge(data.status))
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

    container.textContent = ""

    const wrapper = document.createElement("div")
    wrapper.className = "overflow-x-auto"

    const table = document.createElement("table")
    table.className = "table overflow-x-auto"
    table.dataset.videoExportsTarget = "table"

    const thead = document.createElement("thead")
    const headerRow = document.createElement("tr")
    for (const heading of [
      "Name",
      "File size",
      "Created at",
      "Status",
      "Actions",
    ]) {
      const th = document.createElement("th")
      th.textContent = heading
      headerRow.appendChild(th)
    }
    thead.appendChild(headerRow)
    table.appendChild(thead)

    const tbody = document.createElement("tbody")
    table.appendChild(tbody)

    wrapper.appendChild(table)
    container.appendChild(wrapper)
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

    if (data.status === "failed") {
      const retryBtn = document.createElement("button")
      retryBtn.type = "button"
      retryBtn.className = "px-4 py-2 bg-amber-500 text-white rounded-md"
      retryBtn.dataset.action = "click->video-exports#retry"
      retryBtn.dataset.retryConfig = JSON.stringify(data.config || {})
      retryBtn.dataset.retryTrackId = data.track_id || ""
      retryBtn.dataset.retryStartAt = data.start_at || ""
      retryBtn.dataset.retryEndAt = data.end_at || ""
      retryBtn.dataset.retryLink = ""
      retryBtn.textContent = "Retry"
      cell.appendChild(retryBtn)
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
