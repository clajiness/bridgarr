import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["action", "cell", "panel", "selectedCount", "submit"]

  connect() {
    this.refresh()
  }

  refresh() {
    const action = this.actionTarget.value
    const selectedCount = this.cellTargets.filter((cell) => cell.checked).length

    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.bulkAction !== action
    })

    this.selectedCountTarget.textContent = this.selectionLabel(selectedCount)
    this.submitTarget.textContent = this.submitLabel(action, selectedCount)
    this.submitTarget.disabled = selectedCount === 0 || action.length === 0
  }

  selectionLabel(count) {
    return `${count} ${count === 1 ? "cell" : "cells"} selected`
  }

  submitLabel(action, count) {
    const noun = count === 1 ? "assignment" : "assignments"

    switch (action) {
      case "create":
        return `Create ${count} ${noun}`
      case "search_modes":
        return `Review search modes for ${count} ${noun}`
      case "direct":
        return `Review direct mode for ${count} ${noun}`
      case "bridged":
        return `Review bridged mode for ${count} ${noun}`
      case "categories":
        return `Review categories for ${count} ${noun}`
      case "preview":
      case "test":
        return `Preview ${count} ${noun}`
      case "sync":
        return `Review sync for ${count} ${noun}`
      default:
        return "Choose a bulk action"
    }
  }
}
