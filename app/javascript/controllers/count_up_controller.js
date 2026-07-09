import { Controller } from "@hotwired/stimulus"

const previousValues = new Map()

export default class extends Controller {
  static values = {
    end: Number,
    decimals: { type: Number, default: 0 },
    suffix: { type: String, default: "" },
    key: String
  }

  connect() {
    this.connected = true
    const startValue = this.startValue()
    this.animate(startValue, this.endValue)
  }

  disconnect() {
    this.connected = false
    this.rememberValue(this.endValue)
    if (this.frame) cancelAnimationFrame(this.frame)
  }

  endValueChanged(newValue, oldValue) {
    if (!this.connected || oldValue === undefined || newValue === oldValue) return

    this.animate(oldValue, newValue)
  }

  animate(fromValue, toValue) {
    if (this.frame) cancelAnimationFrame(this.frame)

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.render(toValue)
      this.rememberValue(toValue)
      return
    }

    const start = performance.now()
    const duration = 520

    const tick = (now) => {
      const progress = Math.min((now - start) / duration, 1)
      const eased = 1 - Math.pow(1 - progress, 3)
      this.render(fromValue + ((toValue - fromValue) * eased))

      if (progress < 1) {
        this.frame = requestAnimationFrame(tick)
      } else {
        this.rememberValue(toValue)
        this.frame = null
      }
    }

    this.frame = requestAnimationFrame(tick)
  }

  startValue() {
    if (!this.hasKeyValue) return 0

    return previousValues.has(this.keyValue) ? previousValues.get(this.keyValue) : 0
  }

  rememberValue(value) {
    if (!this.hasKeyValue) return

    previousValues.set(this.keyValue, value)
  }

  render(value) {
    const formatted = new Intl.NumberFormat(undefined, {
      maximumFractionDigits: this.decimalsValue,
      minimumFractionDigits: this.decimalsValue
    }).format(value)

    this.element.textContent = `${formatted}${this.suffixValue}`
  }
}
