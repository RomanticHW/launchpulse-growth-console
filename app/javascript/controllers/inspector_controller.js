import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "section",
    "sectionNav",
    "recommendation",
    "experiment",
    "overview",
    "recommendationEmpty",
    "experimentEmpty",
    "selectedName",
    "selectedMeta",
    "clearButton",
    "sidebar"
  ]
  static values = {
    sectionId: String,
    previewSectionId: String,
    defaultTitle: { type: String, default: "站点概览" },
    defaultMeta: { type: String, default: "查看全站数据、优化建议、实验和最近事件" }
  }

  initialize() {
    this.pulseTimers = new Map()
    this.renderQueued = false
    this.renderFrame = null
  }

  connect() {
    this.render()
  }

  disconnect() {
    this.pulseTimers.forEach(timer => clearTimeout(timer))
    this.pulseTimers.clear()
    if (this.renderFrame) cancelAnimationFrame(this.renderFrame)
  }

  select(event) {
    event.preventDefault()

    const clickedId = event.currentTarget.dataset.sectionId
    if (!clickedId) return

    this.toggleSection(clickedId)
  }

  selectSection(event) {
    if (this.isInteractiveElement(event.target)) return

    event.preventDefault()

    const clickedId = event.currentTarget.dataset.sectionId
    if (!clickedId) return

    this.toggleSection(clickedId)
  }

  handleSectionKeydown(event) {
    if (event.key !== "Enter" && event.key !== " ") return
    if (event.target !== event.currentTarget && this.isInteractiveElement(event.target)) return

    event.preventDefault()

    const sectionId = event.currentTarget.dataset.sectionId
    if (!sectionId) return

    this.toggleSection(sectionId)
  }

  clear() {
    this.sectionIdValue = ""
  }

  selectCard(event) {
    event.preventDefault()

    const sectionId = event.currentTarget.dataset.sectionId
    if (!sectionId) return

    this.sectionIdValue = sectionId
    this.scrollToSection(sectionId)
  }

  recommendationTargetConnected() {
    this.queueRender()
  }

  experimentTargetConnected() {
    this.queueRender()
  }

  overviewTargetConnected() {
    this.queueRender()
  }

  sectionIdValueChanged() {
    this.updateUrl()
    this.render()
  }

  queueRender() {
    if (this.renderQueued) return

    this.renderQueued = true
    this.renderFrame = requestAnimationFrame(() => {
      this.renderQueued = false
      this.renderFrame = null
      this.render()
    })
  }

  updateUrl() {
    const url = new URL(window.location.href)
    const selectedId = this.sectionIdValue

    if (selectedId) {
      url.searchParams.set("selected_section_id", selectedId)
    } else {
      url.searchParams.delete("selected_section_id")
    }

    if (!selectedId || (this.hasPreviewSectionIdValue && selectedId !== this.previewSectionIdValue)) {
      url.searchParams.delete("preview_recommendation_id")
    }

    window.history.replaceState({}, "", `${url.pathname}${url.search}${url.hash}`)
  }

  render() {
    const selectedId = this.sectionIdValue
    const selectedSource = this.findSelectedSource(selectedId)

    this.sectionTargets.forEach(target => {
      if (selectedId && target.dataset.sectionId === selectedId) {
        target.dataset.selected = "true"
        target.dataset.spotlight = "focused"
      } else {
        target.dataset.selected = "false"
        if (selectedId) {
          target.dataset.spotlight = "dimmed"
        } else {
          delete target.dataset.spotlight
        }
      }
    })

    this.sectionNavTargets.forEach(target => {
      target.dataset.selected = selectedId && target.dataset.sectionId === selectedId ? "true" : "false"
    })

    this.selectedNameTargets.forEach(target => {
      target.textContent = selectedSource?.dataset.sectionName || this.defaultTitleValue
    })

    this.selectedMetaTargets.forEach(target => {
      if (selectedSource) {
        target.textContent = `${selectedSource.dataset.sectionKind || "区块"} / 显示相关建议和实验`
      } else {
        target.textContent = this.defaultMetaValue
      }
    })

    this.clearButtonTargets.forEach(target => {
      target.classList.toggle("hidden", !selectedId)
    })

    if (!selectedId) {
      this.overviewTargets.forEach(el => el.classList.remove("hidden"))
      this.recommendationTargets.forEach(el => el.classList.remove("hidden"))
      this.experimentTargets.forEach(el => el.classList.remove("hidden"))
      this.recommendationEmptyTargets.forEach(el => el.classList.add("hidden"))
      this.experimentEmptyTargets.forEach(el => el.classList.add("hidden"))
    } else {
      this.overviewTargets.forEach(el => el.classList.add("hidden"))

      let visibleRecs = 0
      this.recommendationTargets.forEach(el => {
        if (el.dataset.sectionId === selectedId) {
          el.classList.remove("hidden")
          visibleRecs++
        } else {
          el.classList.add("hidden")
        }
      })

      if (visibleRecs === 0) {
        this.recommendationEmptyTargets.forEach(el => el.classList.remove("hidden"))
      } else {
        this.recommendationEmptyTargets.forEach(el => el.classList.add("hidden"))
      }

      let visibleExps = 0
      this.experimentTargets.forEach(el => {
        if (el.dataset.sectionId === selectedId) {
          el.classList.remove("hidden")
          visibleExps++
        } else {
          el.classList.add("hidden")
        }
      })

      if (visibleExps === 0) {
        this.experimentEmptyTargets.forEach(el => el.classList.remove("hidden"))
      } else {
        this.experimentEmptyTargets.forEach(el => el.classList.add("hidden"))
      }

      if (this.hasSidebarTarget) {
        this.sidebarTarget.scrollTop = 0
      }
    }
  }

  findSelectedSource(selectedId) {
    if (!selectedId) return null

    return this.sectionTargets.find(target => target.dataset.sectionId === selectedId) ||
      this.sectionNavTargets.find(target => target.dataset.sectionId === selectedId)
  }

  toggleSection(sectionId) {
    if (this.sectionIdValue === sectionId) {
      this.sectionIdValue = ""
    } else {
      this.sectionIdValue = sectionId
    }
  }

  isInteractiveElement(target) {
    return Boolean(target.closest(
      "a, button, input, select, textarea, label, summary, details, [contenteditable='true'], [data-preview-interactive='true']"
    ))
  }

  scrollToSection(sectionId) {
    const target = this.sectionTargets.find(section => section.dataset.sectionId === sectionId)
    if (!target) return

    const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    target.scrollIntoView({
      behavior: prefersReducedMotion ? "auto" : "smooth",
      block: "center",
      inline: "nearest"
    })
    this.pulseSection(target)
  }

  pulseSection(target) {
    target.classList.remove("section-attention-pulse")
    void target.offsetWidth
    target.classList.add("section-attention-pulse")

    clearTimeout(this.pulseTimers.get(target))
    this.pulseTimers.set(target, setTimeout(() => {
      target.classList.remove("section-attention-pulse")
      this.pulseTimers.delete(target)
    }, 1100))
  }
}
