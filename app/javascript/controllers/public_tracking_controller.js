import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    eventType: String,
    sectionUid: String,
    formId: Number,
    productKey: String,
    metadata: Object
  }

  send(event) {
    if (this.sent && this.eventTypeValue === "form_start") return
    this.sent = true
    const metadata = { ...(this.hasMetadataValue ? this.metadataValue : {}) }
    const target = event.target?.textContent?.trim()
    if (target) metadata.target = target

    const body = {
      event_type: this.eventTypeValue,
      metadata
    }
    if (this.hasSectionUidValue) body.section_uid = this.sectionUidValue
    if (this.hasFormIdValue) body.form_id = this.formIdValue
    if (this.hasProductKeyValue) body.product_key = this.productKeyValue

    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: JSON.stringify(body),
      keepalive: true
    }).catch(() => {})
  }
}
