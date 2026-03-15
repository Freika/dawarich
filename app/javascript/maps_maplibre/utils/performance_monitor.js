/**
 * Performance monitoring utility
 * Tracks timing metrics and memory usage
 */
export class PerformanceMonitor {
  constructor() {
    this.marks = new Map()
    this.metrics = []
  }

  /**
   * Start timing
   * @param {string} name
   */
  mark(name) {
    this.marks.set(name, performance.now())
  }

  /**
   * End timing and record
   * @param {string} name
   * @returns {number} Duration in ms
   */
  measure(name) {
    const startTime = this.marks.get(name)
    if (!startTime) {
      console.warn(`No mark found for: ${name}`)
      return 0
    }

    const duration = performance.now() - startTime
    this.marks.delete(name)

    this.metrics.push({
      name,
      duration,
      timestamp: Date.now(),
    })

    return duration
  }

  /**
   * Get performance report
   * @returns {Object}
   */
  getReport() {
    const grouped = this.metrics.reduce((acc, metric) => {
      if (!acc[metric.name]) {
        acc[metric.name] = []
      }
      acc[metric.name].push(metric.duration)
      return acc
    }, {})

    const report = {}
    for (const [name, durations] of Object.entries(grouped)) {
      const avg = durations.reduce((a, b) => a + b, 0) / durations.length
      const min = Math.min(...durations)
      const max = Math.max(...durations)

      report[name] = {
        count: durations.length,
        avg: Math.round(avg),
        min: Math.round(min),
        max: Math.round(max),
      }
    }

    return report
  }

  /**
   * Get memory usage
   * @returns {Object|null}
   */
  getMemoryUsage() {
    if (!performance.memory) return null

    return {
      used: Math.round(performance.memory.usedJSHeapSize / 1048576),
      total: Math.round(performance.memory.totalJSHeapSize / 1048576),
      limit: Math.round(performance.memory.jsHeapSizeLimit / 1048576),
    }
  }

  /**
   * Log report to console
   */
  logReport() {
    console.group("Performance Report")
    console.table(this.getReport())

    const memory = this.getMemoryUsage()
    if (memory) {
      console.log(
        `Memory: ${memory.used}MB / ${memory.total}MB (limit: ${memory.limit}MB)`,
      )
    }

    console.groupEnd()
  }

  clear() {
    this.marks.clear()
    this.metrics = []
  }
}

export const performanceMonitor = new PerformanceMonitor()
