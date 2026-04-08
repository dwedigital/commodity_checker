import { Controller } from "@hotwired/stimulus"

// Simple line chart controller using Canvas API
// No external dependencies, CSP-compliant
export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    data: Object,
    color: { type: String, default: "#2D1E2F" }
  }

  connect() {
    this.draw()
    window.addEventListener("resize", this.handleResize.bind(this))
  }

  disconnect() {
    window.removeEventListener("resize", this.handleResize.bind(this))
  }

  // Redraw when data value changes (Turbo navigation)
  dataValueChanged() {
    this.draw()
  }

  handleResize() {
    this.draw()
  }

  draw() {
    const canvas = this.canvasTarget
    const ctx = canvas.getContext("2d")
    const data = this.dataValue
    const entries = Object.entries(data)

    if (entries.length === 0) return

    // Set canvas size to match container
    const container = canvas.parentElement
    const dpr = window.devicePixelRatio || 1
    canvas.width = container.clientWidth * dpr
    canvas.height = container.clientHeight * dpr
    canvas.style.width = `${container.clientWidth}px`
    canvas.style.height = `${container.clientHeight}px`
    ctx.scale(dpr, dpr)

    const width = container.clientWidth
    const height = container.clientHeight
    const padding = { top: 20, right: 20, bottom: 30, left: 50 }

    // Clear canvas
    ctx.clearRect(0, 0, width, height)

    // Calculate scales
    const values = entries.map(([_, v]) => v)
    const maxValue = Math.max(...values, 1)
    const minValue = 0

    const chartWidth = width - padding.left - padding.right
    const chartHeight = height - padding.top - padding.bottom

    const xScale = (i) => padding.left + (i / (entries.length - 1 || 1)) * chartWidth
    const yScale = (v) => padding.top + chartHeight - ((v - minValue) / (maxValue - minValue || 1)) * chartHeight

    // Draw grid lines
    ctx.strokeStyle = "#f0f0f0"
    ctx.lineWidth = 1
    const gridLines = 4
    for (let i = 0; i <= gridLines; i++) {
      const y = padding.top + (chartHeight / gridLines) * i
      ctx.beginPath()
      ctx.moveTo(padding.left, y)
      ctx.lineTo(width - padding.right, y)
      ctx.stroke()
    }

    // Draw Y axis labels
    ctx.fillStyle = "#9ca3af"
    ctx.font = "11px system-ui"
    ctx.textAlign = "right"
    ctx.textBaseline = "middle"
    for (let i = 0; i <= gridLines; i++) {
      const value = maxValue - (maxValue / gridLines) * i
      const y = padding.top + (chartHeight / gridLines) * i
      ctx.fillText(Math.round(value).toString(), padding.left - 8, y)
    }

    // Draw area fill
    ctx.beginPath()
    ctx.moveTo(xScale(0), yScale(0))
    entries.forEach(([_, value], i) => {
      ctx.lineTo(xScale(i), yScale(value))
    })
    ctx.lineTo(xScale(entries.length - 1), yScale(0))
    ctx.closePath()
    ctx.fillStyle = this.colorValue + "20"
    ctx.fill()

    // Draw line
    ctx.beginPath()
    ctx.strokeStyle = this.colorValue
    ctx.lineWidth = 2
    ctx.lineJoin = "round"
    ctx.lineCap = "round"
    entries.forEach(([_, value], i) => {
      if (i === 0) {
        ctx.moveTo(xScale(i), yScale(value))
      } else {
        ctx.lineTo(xScale(i), yScale(value))
      }
    })
    ctx.stroke()

    // Draw points
    entries.forEach(([_, value], i) => {
      ctx.beginPath()
      ctx.arc(xScale(i), yScale(value), 3, 0, Math.PI * 2)
      ctx.fillStyle = this.colorValue
      ctx.fill()
    })

    // Draw X axis labels (show first, middle, last)
    ctx.fillStyle = "#9ca3af"
    ctx.font = "10px system-ui"
    ctx.textAlign = "center"
    ctx.textBaseline = "top"

    const labelIndices = entries.length <= 7
      ? entries.map((_, i) => i)
      : [0, Math.floor(entries.length / 2), entries.length - 1]

    labelIndices.forEach(i => {
      if (entries[i]) {
        const [date] = entries[i]
        const label = this.formatDate(date)
        ctx.fillText(label, xScale(i), height - padding.bottom + 8)
      }
    })
  }

  formatDate(dateStr) {
    const date = new Date(dateStr)
    return date.toLocaleDateString("en-GB", { day: "numeric", month: "short" })
  }
}
