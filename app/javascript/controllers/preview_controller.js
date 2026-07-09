import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["viewport", "sizer", "frame", "desktopButton", "mobileButton"]
  static values = {
    defaultMode: { type: String, default: "auto" },
    mobileBreakpoint: { type: Number, default: 640 },
    storageKey: { type: String, default: "launch_pulse.preview_mode" }
  }

  connect() {
    this.resizeObserver = new ResizeObserver(() => this.scheduleScale())
    this.resizeObserver.observe(this.viewportTarget)
    this.resizeObserver.observe(this.frameTarget)

    this.activate(this.initialMode(), { persist: false })
  }

  disconnect() {
    this.resizeObserver?.disconnect()
    if (this.frameRequest) cancelAnimationFrame(this.frameRequest)
  }

  desktop(event) {
    event?.preventDefault()
    this.activate("desktop")
  }

  mobile(event) {
    event?.preventDefault()
    this.activate("mobile")
  }

  activate(mode, { persist = true } = {}) {
    this.mode = mode === "mobile" ? "mobile" : "desktop"
    this.frameTarget.classList.toggle("site-preview-frame--mobile", this.mode === "mobile")
    this.frameTarget.classList.add("max-w-none")
    this.setButtonState(this.mode)
    if (persist) this.rememberMode(this.mode)
    this.scheduleScale()
  }

  initialMode() {
    const savedMode = this.savedMode()
    if (savedMode) return savedMode

    if (this.defaultModeValue === "mobile" || this.defaultModeValue === "desktop") return this.defaultModeValue
    if (window.matchMedia(`(max-width: ${this.mobileBreakpointValue}px)`).matches) return "mobile"

    return "desktop"
  }

  savedMode() {
    try {
      const mode = window.localStorage.getItem(this.storageKeyValue)
      return ["desktop", "mobile"].includes(mode) ? mode : null
    } catch (_error) {
      return null
    }
  }

  rememberMode(mode) {
    try {
      window.localStorage.setItem(this.storageKeyValue, mode)
    } catch (_error) {
      // localStorage can be disabled in private or restricted browser contexts.
    }
  }

  scheduleScale() {
    if (this.frameRequest) cancelAnimationFrame(this.frameRequest)
    this.frameRequest = requestAnimationFrame(() => {
      this.applyScale()
      this.frameRequest = null
    })
  }

  applyScale() {
    const targetWidth = this.mode === "mobile" ? 390 : 1024
    const availableWidth = this.viewportTarget.clientWidth
    const scale = Math.min(1, availableWidth / targetWidth)
    const frameHeight = this.frameTarget.offsetHeight

    this.sizerTarget.style.width = `${targetWidth * scale}px`
    this.sizerTarget.style.height = `${frameHeight * scale}px`
    this.frameTarget.style.width = `${targetWidth}px`
    this.frameTarget.style.transform = `scale(${scale})`
    this.frameTarget.dataset.previewScale = scale.toFixed(3)
  }

  setButtonState(activeMode) {
    const desktopActive = activeMode === "desktop"
    this.desktopButtonTarget.dataset.active = desktopActive ? "true" : "false"
    this.mobileButtonTarget.dataset.active = desktopActive ? "false" : "true"
    this.desktopButtonTarget.setAttribute("aria-pressed", desktopActive ? "true" : "false")
    this.mobileButtonTarget.setAttribute("aria-pressed", desktopActive ? "false" : "true")
  }
}
