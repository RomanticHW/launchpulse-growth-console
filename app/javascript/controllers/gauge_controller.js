import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["ring"]
  static values = { score: Number }

  connect() {
    if (!this.hasRingTarget) return

    const finalOffset = 100 - Math.max(0, Math.min(this.scoreValue, 100))

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.ringTarget.style.strokeDashoffset = finalOffset
      return
    }

    this.ringTarget.style.strokeDashoffset = 100
    requestAnimationFrame(() => {
      this.ringTarget.style.transition = "stroke-dashoffset 560ms var(--ease-signature)"
      this.ringTarget.style.strokeDashoffset = finalOffset
    })
  }
}
