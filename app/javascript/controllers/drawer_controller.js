import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "backdrop", "trigger"]

  connect() {
    this.closeTimer = null
  }

  open(event) {
    event?.preventDefault()
    clearTimeout(this.closeTimer)
    this.previouslyFocusedElement = this.restorableElement(document.activeElement)

    this.panelTarget.hidden = false
    this.backdropTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")

    requestAnimationFrame(() => {
      this.panelTarget.classList.remove("-translate-x-full", "opacity-0")
      this.backdropTarget.classList.remove("opacity-0")
    })

    this.panelTarget.focus({ preventScroll: true })
  }

  trapFocus(event) {
    if (event.key !== "Tab") return
    if (this.panelTarget.hidden) return

    const focusableElements = this.focusableElements()
    if (focusableElements.length === 0) {
      event.preventDefault()
      this.panelTarget.focus({ preventScroll: true })
      return
    }

    const firstElement = focusableElements[0]
    const lastElement = focusableElements[focusableElements.length - 1]

    if (event.shiftKey && (document.activeElement === firstElement || document.activeElement === this.panelTarget)) {
      event.preventDefault()
      lastElement.focus()
    } else if (!event.shiftKey && document.activeElement === lastElement) {
      event.preventDefault()
      firstElement.focus()
    } else if (!this.panelTarget.contains(document.activeElement)) {
      event.preventDefault()
      firstElement.focus()
    }
  }

  close(event) {
    event?.preventDefault()
    if (this.panelTarget.hidden) return

    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.panelTarget.classList.add("-translate-x-full", "opacity-0")
    this.backdropTarget.classList.add("opacity-0")

    this.closeTimer = setTimeout(() => {
      this.panelTarget.hidden = true
      this.backdropTarget.hidden = true
    }, 180)

    const focusTarget = this.previouslyFocusedElement?.isConnected ? this.previouslyFocusedElement : this.triggerTarget
    focusTarget.focus({ preventScroll: true })
  }

  focusableElements() {
    return Array.from(this.panelTarget.querySelectorAll(
      "a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex='-1'])"
    )).filter(element => element.offsetParent !== null || element === document.activeElement)
  }

  restorableElement(element) {
    if (!element || element === document.body || !element.isConnected) return this.triggerTarget
    return element
  }
}
