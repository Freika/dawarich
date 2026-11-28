/**
 * Moving between the replay's days.
 * Mixed into ReplayManager; `this` is the ReplayManager.
 */
export const dayNavigation = {
  /**
   * Navigate to previous day
   * @returns {boolean} Whether navigation was successful
   */
  prevDay() {
    if (this.currentDayIndex > 0) {
      this.currentDayIndex--
      this.buildMinuteIndex()
      this.cycleIndex = 0
      this.pinnedPoint = null
      return true
    }
    return false
  },

  /**
   * Navigate to next day
   * @returns {boolean} Whether navigation was successful
   */
  nextDay() {
    if (this.currentDayIndex < this.availableDays.length - 1) {
      this.currentDayIndex++
      this.buildMinuteIndex()
      this.cycleIndex = 0
      this.pinnedPoint = null
      return true
    }
    return false
  },

  /**
   * Check if previous day navigation is available
   * @returns {boolean}
   */
  canGoPrev() {
    return this.currentDayIndex > 0
  },

  /**
   * Check if next day navigation is available
   * @returns {boolean}
   */
  canGoNext() {
    return this.currentDayIndex < this.availableDays.length - 1
  },

  /**
   * Navigate to a specific day by key
   * @param {string} dayKey - Day key like '2025-01-15'
   * @returns {boolean} Whether navigation was successful
   */
  goToDay(dayKey) {
    const index = this.availableDays.indexOf(dayKey)
    if (index === -1 || index === this.currentDayIndex) return false

    this.currentDayIndex = index
    this.buildMinuteIndex()
    this.cycleIndex = 0
    this.pinnedPoint = null
    return true
  },

  /**
   * Get points for a specific day
   * @param {string} dayKey - Day key like '2025-01-15'
   * @returns {Array} Points for that day, or empty array
   */
  getPointsForDay(dayKey) {
    return this.pointsByDay[dayKey] || []
  },
}
