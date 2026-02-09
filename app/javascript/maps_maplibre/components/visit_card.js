/**
 * Visit card component for rendering individual visit cards in the side panel
 */
export class VisitCard {
  /**
   * Create HTML for a visit card
   * @param {Object} visit - Visit object with id, name, status, started_at, ended_at, duration, place
   * @param {Object} options - { isSelected, onSelect, onConfirm, onDecline, onHover }
   * @returns {string} HTML string
   */
  static create(visit, options = {}) {
    const {
      isSelected = false,
      onSelect,
      onConfirm,
      onDecline,
      onHover,
      timezone = "UTC",
    } = options
    const isSuggested = visit.status === "suggested"
    const isConfirmed = visit.status === "confirmed"
    const isDeclined = visit.status === "declined"

    // Format date and time
    const startDate = new Date(visit.started_at)
    const endDate = new Date(visit.ended_at)
    const dateStr = startDate.toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric",
      timeZone: timezone,
    })
    const timeRange = `${startDate.toLocaleTimeString("en-US", {
      hour: "2-digit",
      minute: "2-digit",
      timeZone: timezone,
    })} - ${endDate.toLocaleTimeString("en-US", {
      hour: "2-digit",
      minute: "2-digit",
      timeZone: timezone,
    })}`

    // Format duration (duration is in minutes from the backend)
    const hours = Math.floor(visit.duration / 60)
    const minutes = visit.duration % 60
    const durationStr = hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`

    // Border style based on status
    const borderClass = isSuggested ? "border-dashed" : ""
    const bgClass = isDeclined ? "bg-base-200 opacity-60" : "bg-base-100"
    const selectedClass = isSelected ? "ring-2 ring-primary" : ""

    return `
      <div class="visit-card card ${bgClass} ${borderClass} ${selectedClass} border-2 border-base-content/20 mb-2 hover:shadow-md transition-all relative"
           data-visit-id="${visit.id}"
           data-visit-status="${visit.status}"
           onmouseenter="this.querySelector('.visit-checkbox').classList.remove('hidden')"
           onmouseleave="if(!this.querySelector('.visit-checkbox input').checked) this.querySelector('.visit-checkbox').classList.add('hidden')">

        <!-- Checkbox (hidden by default, shown on hover) -->
        <div class="visit-checkbox absolute top-3 right-3 z-10 ${isSelected ? "" : "hidden"}">
          <input type="checkbox"
                 class="checkbox checkbox-primary checkbox-sm"
                 ${isSelected ? "checked" : ""}
                 data-visit-select="${visit.id}"
                 onclick="event.stopPropagation()">
        </div>

        <div class="card-body p-3">
          <!-- Visit Name -->
          <h3 class="card-title text-sm font-semibold mb-2">
            ${visit.name || visit.place?.name || "Unnamed Visit"}
          </h3>

          <!-- Date and Time -->
          <div class="text-xs text-base-content/70 space-y-1">
            <div class="flex items-center gap-1.5">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
              </svg>
              <span class="truncate">${dateStr}</span>
            </div>
            <div class="flex items-center gap-1.5">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <span class="truncate">${timeRange}</span>
            </div>
            <div class="flex items-center gap-1.5">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />
              </svg>
              <span class="truncate">${durationStr}</span>
            </div>
          </div>

          <!-- Action buttons for suggested visits -->
          ${
            isSuggested
              ? `
            <div class="card-actions justify-end mt-3 gap-1.5">
              <button class="btn btn-xs btn-outline btn-error" data-visit-decline="${visit.id}">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
                Decline
              </button>
              <button class="btn btn-xs btn-primary" data-visit-confirm="${visit.id}">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                </svg>
                Confirm
              </button>
            </div>
          `
              : ""
          }

          <!-- Status badge for confirmed/declined visits -->
          ${
            isConfirmed || isDeclined
              ? `
            <div class="mt-2">
              <span class="badge badge-xs ${isConfirmed ? "badge-success" : "badge-error"}">
                ${visit.status}
              </span>
            </div>
          `
              : ""
          }
        </div>
      </div>
    `
  }

  /**
   * Create bulk action buttons HTML
   * @param {number} selectedCount - Number of selected visits
   * @returns {string} HTML string
   */
  static createBulkActions(selectedCount) {
    if (selectedCount < 2) return ""

    return `
      <div class="bulk-actions-panel sticky bottom-0 bg-base-100 border-t border-base-300 p-4 mt-4 space-y-2">
        <div class="text-sm font-medium mb-3">
          ${selectedCount} visit${selectedCount === 1 ? "" : "s"} selected
        </div>
        <div class="grid grid-cols-3 gap-2">
          <button class="btn btn-sm btn-outline" data-bulk-merge>
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4" />
            </svg>
            Merge
          </button>
          <button class="btn btn-sm btn-primary" data-bulk-confirm>
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
            </svg>
            Confirm
          </button>
          <button class="btn btn-sm btn-outline btn-error" data-bulk-decline>
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
            Decline
          </button>
        </div>
      </div>
    `
  }
}
