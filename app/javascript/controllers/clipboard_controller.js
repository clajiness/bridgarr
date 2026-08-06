import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  async copy() {
    const originalText = this.element.textContent

    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "text/plain" } })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      await navigator.clipboard.writeText(await response.text())
      this.element.textContent = "Diagnostic copied"
    } catch (_error) {
      this.element.textContent = "Could not copy diagnostic"
    } finally {
      window.setTimeout(() => { this.element.textContent = originalText }, 2500)
    }
  }
}
