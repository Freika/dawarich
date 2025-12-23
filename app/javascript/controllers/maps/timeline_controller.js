import { Controller } from '@hotwired/stimulus'

/**
 * Timeline controller for map visualization
 * Displays a temporal graph and slider to navigate through location history
 */
export default class extends Controller {
  static targets = [
    'canvas',
    'slider',
    'playButton',
    'currentTime',
    'startLabel',
    'endLabel',
    'graphTypeSelect'
  ]

  static values = {
    startTimestamp: Number,
    endTimestamp: Number,
    currentStart: Number,
    currentEnd: Number
  }

  connect() {
    console.log('Timeline controller connected')
    this.points = []
    this.isPlaying = false
    this.playbackSpeed = 1000 // ms per step
    this.playbackInterval = null
    this.graphType = 'speed' // speed, battery, elevation

    this.initializeCanvas()
    this.bindEvents()
  }

  disconnect() {
    if (this.playbackInterval) {
      clearInterval(this.playbackInterval)
    }
    this.unbindEvents()
  }

  initializeCanvas() {
    if (!this.hasCanvasTarget) return

    const canvas = this.canvasTarget
    const container = canvas.parentElement

    // Set canvas size to match container
    const resizeCanvas = () => {
      const rect = container.getBoundingClientRect()
      canvas.width = rect.width
      canvas.height = rect.height
      this.draw()
    }

    this.resizeCanvas = resizeCanvas
    resizeCanvas()
  }

  bindEvents() {
    window.addEventListener('resize', this.resizeCanvas)

    // Listen for points data from map controller
    document.addEventListener('timeline:updateData', this.handleDataUpdate.bind(this))
  }

  unbindEvents() {
    window.removeEventListener('resize', this.resizeCanvas)
    document.removeEventListener('timeline:updateData', this.handleDataUpdate.bind(this))
  }

  handleDataUpdate(event) {
    const { points, startTimestamp, endTimestamp } = event.detail
    this.points = points || []
    this.startTimestampValue = startTimestamp
    this.endTimestampValue = endTimestamp
    this.currentStartValue = startTimestamp
    this.currentEndValue = endTimestamp

    this.updateLabels()
    this.draw()
  }

  draw() {
    if (!this.hasCanvasTarget || this.points.length === 0) return

    const canvas = this.canvasTarget
    const ctx = canvas.getContext('2d')
    const width = canvas.width
    const height = canvas.height

    // Clear canvas
    ctx.clearRect(0, 0, width, height)

    // Draw background
    ctx.fillStyle = '#1a1a2e'
    ctx.fillRect(0, 0, width, height)

    // Draw grid
    this.drawGrid(ctx, width, height)

    // Draw graph based on selected type
    switch (this.graphType) {
      case 'speed':
        this.drawSpeedGraph(ctx, width, height)
        break
      case 'battery':
        this.drawBatteryGraph(ctx, width, height)
        break
      case 'elevation':
        this.drawElevationGraph(ctx, width, height)
        break
    }

    // Draw time cursor
    this.drawTimeCursor(ctx, width, height)
  }

  drawGrid(ctx, width, height) {
    ctx.strokeStyle = '#2a2a3e'
    ctx.lineWidth = 1

    // Horizontal lines
    const horizontalLines = 5
    for (let i = 0; i <= horizontalLines; i++) {
      const y = (height / horizontalLines) * i
      ctx.beginPath()
      ctx.moveTo(0, y)
      ctx.lineTo(width, y)
      ctx.stroke()
    }

    // Vertical lines (time markers)
    const verticalLines = 10
    for (let i = 0; i <= verticalLines; i++) {
      const x = (width / verticalLines) * i
      ctx.beginPath()
      ctx.moveTo(x, 0)
      ctx.lineTo(x, height)
      ctx.stroke()
    }
  }

  drawSpeedGraph(ctx, width, height) {
    if (this.points.length < 2) return

    const timeRange = this.endTimestampValue - this.startTimestampValue
    if (timeRange === 0) return

    // Calculate speeds between consecutive points
    const speeds = []
    for (let i = 1; i < this.points.length; i++) {
      const p1 = this.points[i - 1]
      const p2 = this.points[i]

      const timeDiff = p2.timestamp - p1.timestamp // seconds
      if (timeDiff === 0) continue

      // Calculate distance using Haversine formula
      const distance = this.calculateDistance(
        p1.latitude, p1.longitude,
        p2.latitude, p2.longitude
      )

      // Speed in km/h
      const speed = (distance / 1000) / (timeDiff / 3600)

      speeds.push({
        timestamp: p2.timestamp,
        speed: Math.min(speed, 150) // Cap at 150 km/h for visualization
      })
    }

    if (speeds.length === 0) return

    // Find max speed for scaling
    const maxSpeed = Math.max(...speeds.map(s => s.speed))

    // Draw speed graph
    ctx.strokeStyle = '#00ff88'
    ctx.lineWidth = 2
    ctx.beginPath()

    speeds.forEach((item, index) => {
      const x = ((item.timestamp - this.startTimestampValue) / timeRange) * width
      const y = height - (item.speed / maxSpeed) * height * 0.9 // 90% of height

      if (index === 0) {
        ctx.moveTo(x, y)
      } else {
        ctx.lineTo(x, y)
      }
    })

    ctx.stroke()

    // Draw speed labels
    ctx.fillStyle = '#888'
    ctx.font = '10px sans-serif'
    ctx.fillText('0 km/h', 5, height - 5)
    ctx.fillText(`${Math.round(maxSpeed)} km/h`, 5, 15)
  }

  drawBatteryGraph(ctx, width, height) {
    if (this.points.length === 0) return

    const timeRange = this.endTimestampValue - this.startTimestampValue
    if (timeRange === 0) return

    // Filter points with battery data
    const batteryPoints = this.points.filter(p => p.battery !== null && p.battery !== undefined)
    if (batteryPoints.length === 0) return

    // Draw battery graph
    ctx.strokeStyle = '#ffaa00'
    ctx.lineWidth = 2
    ctx.beginPath()

    batteryPoints.forEach((point, index) => {
      const x = ((point.timestamp - this.startTimestampValue) / timeRange) * width
      const y = height - (point.battery / 100) * height * 0.9

      if (index === 0) {
        ctx.moveTo(x, y)
      } else {
        ctx.lineTo(x, y)
      }
    })

    ctx.stroke()

    // Draw battery labels
    ctx.fillStyle = '#888'
    ctx.font = '10px sans-serif'
    ctx.fillText('0%', 5, height - 5)
    ctx.fillText('100%', 5, 15)
  }

  drawElevationGraph(ctx, width, height) {
    if (this.points.length === 0) return

    const timeRange = this.endTimestampValue - this.startTimestampValue
    if (timeRange === 0) return

    // Filter points with altitude data
    const altitudePoints = this.points.filter(p => p.altitude !== null && p.altitude !== undefined)
    if (altitudePoints.length === 0) return

    // Find min/max altitude
    const altitudes = altitudePoints.map(p => p.altitude)
    const minAlt = Math.min(...altitudes)
    const maxAlt = Math.max(...altitudes)
    const altRange = maxAlt - minAlt || 1

    // Draw elevation graph
    ctx.strokeStyle = '#00aaff'
    ctx.lineWidth = 2
    ctx.beginPath()

    altitudePoints.forEach((point, index) => {
      const x = ((point.timestamp - this.startTimestampValue) / timeRange) * width
      const y = height - ((point.altitude - minAlt) / altRange) * height * 0.9

      if (index === 0) {
        ctx.moveTo(x, y)
      } else {
        ctx.lineTo(x, y)
      }
    })

    ctx.stroke()

    // Draw elevation labels
    ctx.fillStyle = '#888'
    ctx.font = '10px sans-serif'
    ctx.fillText(`${Math.round(minAlt)}m`, 5, height - 5)
    ctx.fillText(`${Math.round(maxAlt)}m`, 5, 15)
  }

  drawTimeCursor(ctx, width, height) {
    const timeRange = this.endTimestampValue - this.startTimestampValue
    if (timeRange === 0) return

    const cursorX = ((this.currentStartValue - this.startTimestampValue) / timeRange) * width

    // Draw vertical line
    ctx.strokeStyle = '#ff0066'
    ctx.lineWidth = 2
    ctx.beginPath()
    ctx.moveTo(cursorX, 0)
    ctx.lineTo(cursorX, height)
    ctx.stroke()

    // Draw time label
    const date = new Date(this.currentStartValue * 1000)
    const timeStr = date.toLocaleTimeString()

    ctx.fillStyle = '#ff0066'
    ctx.font = 'bold 12px sans-serif'
    const textWidth = ctx.measureText(timeStr).width
    const labelX = Math.min(Math.max(cursorX - textWidth / 2, 0), width - textWidth)
    ctx.fillText(timeStr, labelX, height - 10)
  }

  // Haversine formula for distance calculation
  calculateDistance(lat1, lon1, lat2, lon2) {
    const R = 6371000 // Earth radius in meters
    const φ1 = lat1 * Math.PI / 180
    const φ2 = lat2 * Math.PI / 180
    const Δφ = (lat2 - lat1) * Math.PI / 180
    const Δλ = (lon2 - lon1) * Math.PI / 180

    const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
              Math.cos(φ1) * Math.cos(φ2) *
              Math.sin(Δλ / 2) * Math.sin(Δλ / 2)
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

    return R * c
  }

  // Slider interaction
  updateTimeFromSlider(event) {
    const sliderValue = parseInt(event.target.value)
    const timeRange = this.endTimestampValue - this.startTimestampValue
    const newTimestamp = this.startTimestampValue + (sliderValue / 100) * timeRange

    this.currentStartValue = newTimestamp
    this.draw()
    this.updateCurrentTimeLabel()
    this.notifyMapController()
  }

  updateCurrentTimeLabel() {
    if (!this.hasCurrentTimeTarget) return

    const date = new Date(this.currentStartValue * 1000)
    this.currentTimeTarget.textContent = date.toLocaleString()
  }

  updateLabels() {
    if (this.hasStartLabelTarget) {
      const startDate = new Date(this.startTimestampValue * 1000)
      this.startLabelTarget.textContent = startDate.toLocaleDateString()
    }

    if (this.hasEndLabelTarget) {
      const endDate = new Date(this.endTimestampValue * 1000)
      this.endLabelTarget.textContent = endDate.toLocaleDateString()
    }
  }

  changeGraphType(event) {
    this.graphType = event.target.value
    this.draw()
  }

  togglePlayback() {
    this.isPlaying = !this.isPlaying

    if (this.isPlaying) {
      this.startPlayback()
      if (this.hasPlayButtonTarget) {
        this.playButtonTarget.innerHTML = `
          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zM7 8a1 1 0 012 0v4a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v4a1 1 0 102 0V8a1 1 0 00-1-1z" clip-rule="evenodd" />
          </svg>
        `
      }
    } else {
      this.stopPlayback()
      if (this.hasPlayButtonTarget) {
        this.playButtonTarget.innerHTML = `
          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z" clip-rule="evenodd" />
          </svg>
        `
      }
    }
  }

  startPlayback() {
    const timeRange = this.endTimestampValue - this.startTimestampValue
    const step = timeRange / 200 // 200 steps across the range

    this.playbackInterval = setInterval(() => {
      this.currentStartValue += step

      if (this.currentStartValue >= this.endTimestampValue) {
        this.currentStartValue = this.startTimestampValue // Loop back
      }

      // Update slider position
      if (this.hasSliderTarget) {
        const progress = ((this.currentStartValue - this.startTimestampValue) / timeRange) * 100
        this.sliderTarget.value = progress
      }

      this.draw()
      this.updateCurrentTimeLabel()
      this.notifyMapController()
    }, this.playbackSpeed / 200) // Smooth animation
  }

  stopPlayback() {
    if (this.playbackInterval) {
      clearInterval(this.playbackInterval)
      this.playbackInterval = null
    }
  }

  notifyMapController() {
    // Emit event for map controller to filter points
    const event = new CustomEvent('timeline:timeChanged', {
      detail: {
        currentTimestamp: this.currentStartValue,
        startTimestamp: this.startTimestampValue,
        endTimestamp: this.endTimestampValue
      }
    })
    document.dispatchEvent(event)
  }

  // Public method to set data from map controller
  setData(points, startTimestamp, endTimestamp) {
    this.points = points
    this.startTimestampValue = startTimestamp
    this.endTimestampValue = endTimestamp
    this.currentStartValue = startTimestamp
    this.currentEndValue = endTimestamp

    this.updateLabels()
    this.draw()
  }
}
