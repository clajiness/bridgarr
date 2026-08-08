import { Controller } from "@hotwired/stimulus"

// Prevent background page morphs from discarding browser state that has not
// been submitted. Normal visits and form responses are unaffected.
export default class extends Controller {
  connect() {
    this.element.addEventListener("turbo:before-morph-element", this.preserveInteractiveRegion)
    this.element.addEventListener("turbo:before-morph-attribute", this.preserveDisclosureState)
  }

  disconnect() {
    this.element.removeEventListener("turbo:before-morph-element", this.preserveInteractiveRegion)
    this.element.removeEventListener("turbo:before-morph-attribute", this.preserveDisclosureState)
  }

  preserveInteractiveRegion = (event) => {
    const region = event.target
    if (!(region instanceof Element)) return

    if (this.regionHasActiveControl(region) || this.regionHasSelectedText(region) || this.regionHasProtectedForm(region)) {
      event.preventDefault()
    }
  }

  preserveDisclosureState = (event) => {
    if (event.target instanceof HTMLDetailsElement && event.detail.attributeName === "open") {
      event.preventDefault()
    }
  }

  formIsDirty(form) {
    return Array.from(form.elements).some((control) => {
      if (control instanceof HTMLInputElement) return this.inputIsDirty(control)
      if (control instanceof HTMLTextAreaElement) return control.value !== control.defaultValue
      if (control instanceof HTMLSelectElement) {
        return Array.from(control.options).some((option) => option.selected !== option.defaultSelected)
      }

      return false
    })
  }

  inputIsDirty(input) {
    if (["checkbox", "radio"].includes(input.type)) return input.checked !== input.defaultChecked
    if (input.type === "file") return input.files.length > 0
    if (["button", "hidden", "reset", "submit"].includes(input.type)) return false

    return input.value !== input.defaultValue
  }

  regionHasActiveControl(region) {
    const activeElement = document.activeElement

    return activeElement instanceof Element &&
      region.contains(activeElement) &&
      activeElement.matches("button, input, select, textarea, [contenteditable]")
  }

  regionHasSelectedText(region) {
    const selection = window.getSelection()

    return selection &&
      !selection.isCollapsed &&
      selection.anchorNode &&
      selection.focusNode &&
      region.contains(selection.anchorNode) &&
      region.contains(selection.focusNode)
  }

  regionHasProtectedForm(region) {
    return this.formsWithin(region).some((form) => {
      return form.matches('[aria-busy="true"]') || this.formIsDirty(form)
    })
  }

  formsWithin(region) {
    const forms = Array.from(region.querySelectorAll("form"))
    if (region instanceof HTMLFormElement) forms.unshift(region)

    return forms
  }
}
