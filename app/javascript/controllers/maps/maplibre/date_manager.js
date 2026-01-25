import { getMonthStartInTimezone, getMonthEndInTimezone, formatDateForAPIWithTimezone } from '../../../utils/timezone'

/**
 * Manages date formatting and range calculations
 */
export class DateManager {
  /**
   * Format date for API requests (matching V1 format)
   * Format: "YYYY-MM-DDTHH:MM" (e.g., "2025-10-15T00:00", "2025-10-15T23:59")
   * @param {Date} date - The date to format
   * @param {string} timezone - Optional IANA timezone string (e.g., 'Europe/Berlin')
   */
  static formatDateForAPI(date, timezone = null) {
    if (timezone) {
      return formatDateForAPIWithTimezone(date, timezone)
    }

    // Fallback to browser local time for backward compatibility
    const pad = (n) => String(n).padStart(2, '0')
    const year = date.getFullYear()
    const month = pad(date.getMonth() + 1)
    const day = pad(date.getDate())
    const hours = pad(date.getHours())
    const minutes = pad(date.getMinutes())

    return `${year}-${month}-${day}T${hours}:${minutes}`
  }

  /**
   * Parse month selector value to date range
   * @param {string} value - Month selector value in "YYYY-MM" format
   * @param {string} timezone - Optional IANA timezone string (e.g., 'Europe/Berlin')
   */
  static parseMonthSelector(value, timezone = null) {
    const [year, month] = value.split('-').map(Number)

    if (timezone) {
      return {
        startDate: getMonthStartInTimezone(year, month, timezone),
        endDate: getMonthEndInTimezone(year, month, timezone)
      }
    }

    // Fallback to browser local time for backward compatibility
    const startDate = new Date(year, month - 1, 1, 0, 0, 0)
    const lastDay = new Date(year, month, 0).getDate()
    const endDate = new Date(year, month - 1, lastDay, 23, 59, 0)

    return {
      startDate: this.formatDateForAPI(startDate),
      endDate: this.formatDateForAPI(endDate)
    }
  }
}
