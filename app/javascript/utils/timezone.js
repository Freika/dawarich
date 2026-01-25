/**
 * Timezone utility functions for consistent date handling.
 * These functions help with timezone-aware date calculations across the application.
 */

/**
 * Get the start of a day in the specified timezone.
 * @param {Date} date - The date object
 * @param {string} timezone - IANA timezone string (e.g., 'Europe/Berlin')
 * @returns {string} ISO date string for start of day (e.g., "2025-01-15T00:00")
 */
export function getDayStartInTimezone(date, timezone = 'UTC') {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  })

  const dateStr = formatter.format(date)
  return `${dateStr}T00:00`
}

/**
 * Get the end of a day in the specified timezone.
 * @param {Date} date - The date object
 * @param {string} timezone - IANA timezone string (e.g., 'Europe/Berlin')
 * @returns {string} ISO date string for end of day (e.g., "2025-01-15T23:59")
 */
export function getDayEndInTimezone(date, timezone = 'UTC') {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  })

  const dateStr = formatter.format(date)
  return `${dateStr}T23:59`
}

/**
 * Get the start of a month in the specified timezone.
 * @param {number} year - The year
 * @param {number} month - The month (1-12)
 * @param {string} timezone - IANA timezone string (e.g., 'Europe/Berlin')
 * @returns {string} ISO date string for start of month (e.g., "2025-01-01T00:00")
 */
export function getMonthStartInTimezone(year, month, timezone = 'UTC') {
  const monthStr = String(month).padStart(2, '0')
  return `${year}-${monthStr}-01T00:00`
}

/**
 * Get the end of a month in the specified timezone.
 * @param {number} year - The year
 * @param {number} month - The month (1-12)
 * @param {string} timezone - IANA timezone string (e.g., 'Europe/Berlin')
 * @returns {string} ISO date string for end of month (e.g., "2025-01-31T23:59")
 */
export function getMonthEndInTimezone(year, month, timezone = 'UTC') {
  const lastDay = new Date(year, month, 0).getDate()
  const monthStr = String(month).padStart(2, '0')
  const dayStr = String(lastDay).padStart(2, '0')
  return `${year}-${monthStr}-${dayStr}T23:59`
}

/**
 * Format a date for API requests in the specified timezone.
 * @param {Date} date - The date to format
 * @param {string} timezone - IANA timezone string (e.g., 'Europe/Berlin')
 * @returns {string} Formatted date string (e.g., "2025-01-15T14:30")
 */
export function formatDateForAPIWithTimezone(date, timezone = 'UTC') {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false
  })

  const parts = formatter.formatToParts(date)
  const getPart = (type) => parts.find(p => p.type === type)?.value || '00'

  const year = getPart('year')
  const month = getPart('month')
  const day = getPart('day')
  const hour = getPart('hour')
  const minute = getPart('minute')

  return `${year}-${month}-${day}T${hour}:${minute}`
}

/**
 * Get the date part (YYYY-MM-DD) from a timestamp in the specified timezone.
 * @param {number} timestamp - Unix timestamp in seconds
 * @param {string} timezone - IANA timezone string (e.g., 'Europe/Berlin')
 * @returns {string} Date string (e.g., "2025-01-15")
 */
export function timestampToDateInTimezone(timestamp, timezone = 'UTC') {
  const date = new Date(timestamp * 1000)
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  })

  return formatter.format(date)
}

/**
 * Get start of today in the specified timezone.
 * @param {string} timezone - IANA timezone string (e.g., 'Europe/Berlin')
 * @returns {string} ISO date string for start of today (e.g., "2025-01-15T00:00")
 */
export function getTodayStartInTimezone(timezone = 'UTC') {
  return getDayStartInTimezone(new Date(), timezone)
}

/**
 * Get end of today in the specified timezone.
 * @param {string} timezone - IANA timezone string (e.g., 'Europe/Berlin')
 * @returns {string} ISO date string for end of today (e.g., "2025-01-15T23:59")
 */
export function getTodayEndInTimezone(timezone = 'UTC') {
  return getDayEndInTimezone(new Date(), timezone)
}
