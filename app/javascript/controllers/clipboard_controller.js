import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "fallback", "status"]
  static values = { report: String }

  connect() {
    this.resetTimeout = null
  }

  disconnect() {
    window.clearTimeout(this.resetTimeout)
  }

  async copy() {
    if (this.buttonTarget.disabled) return

    this.buttonTarget.disabled = true
    this.fallbackTarget.hidden = true
    this.setResult("Copying diagnostic…", "Copying diagnostic report.")

    try {
      await this.writeReport(this.decodeReport())
      this.setResult("Diagnostic copied", "Diagnostic copied to clipboard.")
      this.scheduleReset()
    } catch (_error) {
      this.setResult("Copy unavailable", "Clipboard access is unavailable. Open the diagnostic report instead.")
      this.fallbackTarget.hidden = false
    } finally {
      this.buttonTarget.disabled = false
    }
  }

  decodeReport() {
    const bytes = Uint8Array.from(window.atob(this.reportValue), (character) => character.charCodeAt(0))
    return new TextDecoder().decode(bytes)
  }

  async writeReport(report) {
    let clipboardError

    if (window.isSecureContext && navigator.clipboard?.writeText) {
      try {
        await navigator.clipboard.writeText(report)
        return
      } catch (error) {
        clipboardError = error
      }
    }

    if (window.isSecureContext && navigator.clipboard?.write && window.ClipboardItem) {
      try {
        const blob = new Blob([report], { type: "text/plain" })
        await navigator.clipboard.write([new ClipboardItem({ "text/plain": blob })])
        return
      } catch (error) {
        clipboardError ||= error
      }
    }

    if (this.copyWithSelection(report)) return

    throw clipboardError || new Error("Clipboard access is unavailable")
  }

  copyWithSelection(report) {
    if (typeof document.execCommand !== "function") return false

    const textarea = document.createElement("textarea")
    textarea.value = report
    textarea.readOnly = true
    textarea.setAttribute("aria-hidden", "true")
    textarea.style.position = "fixed"
    textarea.style.inset = "0 auto auto -9999px"
    textarea.style.opacity = "0"
    document.body.appendChild(textarea)

    try {
      textarea.focus({ preventScroll: true })
      textarea.select()
      textarea.setSelectionRange(0, textarea.value.length)
      return document.execCommand("copy")
    } catch (_error) {
      return false
    } finally {
      textarea.remove()
      this.buttonTarget.focus({ preventScroll: true })
    }
  }

  setResult(buttonText, statusText) {
    window.clearTimeout(this.resetTimeout)
    this.buttonTarget.textContent = buttonText
    this.statusTarget.textContent = statusText
  }

  scheduleReset() {
    this.resetTimeout = window.setTimeout(() => {
      this.buttonTarget.textContent = "Copy diagnostic report"
      this.statusTarget.textContent = ""
    }, 2500)
  }
}
