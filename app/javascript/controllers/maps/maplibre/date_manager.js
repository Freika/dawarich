/**
 * Manages date formatting and range calculations
 */
export class DateManager {
  /**
   * Format date for API requests (matching V1 format)
   * Format: "YYYY-MM-DDTHH:MM" (e.g., "2025-10-15T00:00", "2025-10-15T23:59")
   */
  static formatDateForAPI(date) {
    const pad = (n) => String(n).padStart(2, '0')
    const year = date.getFullYear()
    const month = pad(date.getMonth() + 1)
    const day = pad(date.getDate())
    const hours = pad(date.getHours())
    const minutes = pad(date.getMinutes())

    // Include timezone offset for accurate server-side parsing
    const tzOffset = -date.getTimezoneOffset()
    const tzSign = tzOffset >= 0 ? '+' : '-'
    const tzHours = pad(Math.floor(Math.abs(tzOffset) / 60))
    const tzMinutes = pad(Math.abs(tzOffset) % 60)

    return `${year}-${month}-${day}T${hours}:${minutes}${tzSign}${tzHours}:${tzMinutes}`
  }

  /**
   * Parse month selector value to date range
   */
  static parseMonthSelector(value) {
    const [year, month] = value.split('-')

    const startDate = new Date(year, month - 1, 1, 0, 0, 0)
    const lastDay = new Date(year, month, 0).getDate()
    const endDate = new Date(year, month - 1, lastDay, 23, 59, 0)

    return {
      startDate: this.formatDateForAPI(startDate),
      endDate: this.formatDateForAPI(endDate)
    }
  }
}
