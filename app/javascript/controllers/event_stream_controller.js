import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    limit: { type: Number, default: 25 },
    quietThreshold: { type: Number, default: 5 }
  }

  connect() {
    this.ticking = false
    this.frame = null
    this.addedAt = []
    this.trim()
    this.observer = new MutationObserver((records) => {
      this.markNewRows(records)
      this.scheduleTrim()
    })
    this.observe()
  }

  disconnect() {
    this.observer?.disconnect()
    if (this.frame) cancelAnimationFrame(this.frame)
  }

  scheduleTrim() {
    if (this.ticking) return

    this.ticking = true
    this.frame = requestAnimationFrame(() => {
      this.trim()
      this.ticking = false
      this.frame = null
    })
  }

  trim() {
    // 流量模拟会快速 prepend 事件；这里只保留最近记录，避免演示页面的 DOM 无限制增长。
    const rows = Array.from(this.element.querySelectorAll("[data-event-row]")).filter((row) => row.dataset.eventRemoving !== "true")
    const rowsToRemove = rows.slice(this.limitValue)
    if (rowsToRemove.length === 0) return

    rowsToRemove.forEach((row) => this.removeRow(row))
  }

  observe() {
    this.observer?.observe(this.element, { childList: true })
  }

  markNewRows(records) {
    const rows = records.flatMap((record) => Array.from(record.addedNodes))
      .flatMap((node) => this.eventRowsFor(node))
    if (rows.length === 0) return

    const now = performance.now()
    this.addedAt = this.addedAt.filter((timestamp) => now - timestamp < 1000)
    rows.forEach(() => this.addedAt.push(now))
    const quiet = this.addedAt.length > this.quietThresholdValue

    rows.forEach((row) => {
      if (quiet) row.classList.add("event-row-live--quiet")
    })
  }

  eventRowsFor(node) {
    if (!(node instanceof Element)) return []
    if (node.matches("[data-event-row]")) return [node]
    return Array.from(node.querySelectorAll("[data-event-row]"))
  }

  removeRow(row) {
    row.dataset.eventRemoving = "true"
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      row.remove()
      return
    }

    row.style.setProperty("--event-row-height", `${row.offsetHeight}px`)
    const handleAnimationEnd = (event) => {
      if (event.target === row) {
        row.remove()
      }
    }
    row.addEventListener("animationend", handleAnimationEnd)
    setTimeout(() => row.remove(), 260)
    requestAnimationFrame(() => row.classList.add("event-row-exit"))
  }
}
