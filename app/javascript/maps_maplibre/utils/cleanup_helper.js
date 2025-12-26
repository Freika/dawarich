/**
 * Helper for tracking and cleaning up resources
 * Prevents memory leaks by tracking event listeners, intervals, timeouts, and observers
 */
export class CleanupHelper {
  constructor() {
    this.listeners = []
    this.intervals = []
    this.timeouts = []
    this.observers = []
  }

  addEventListener(target, event, handler, options) {
    target.addEventListener(event, handler, options)
    this.listeners.push({ target, event, handler, options })
  }

  setInterval(callback, delay) {
    const id = setInterval(callback, delay)
    this.intervals.push(id)
    return id
  }

  setTimeout(callback, delay) {
    const id = setTimeout(callback, delay)
    this.timeouts.push(id)
    return id
  }

  addObserver(observer) {
    this.observers.push(observer)
  }

  cleanup() {
    this.listeners.forEach(({ target, event, handler, options }) => {
      target.removeEventListener(event, handler, options)
    })
    this.listeners = []

    this.intervals.forEach(id => clearInterval(id))
    this.intervals = []

    this.timeouts.forEach(id => clearTimeout(id))
    this.timeouts = []

    this.observers.forEach(observer => observer.disconnect())
    this.observers = []
  }
}
