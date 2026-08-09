import { Controller } from "@hotwired/stimulus"

// Prevent background page morphs from discarding browser state that has not
// been submitted. Normal visits and form responses are unaffected.
export default class extends Controller {
  connect() {
    document.addEventListener("turbo:before-fetch-response", this.noteFormResponse)
    document.addEventListener("turbo:render", this.clearFormResponse)
    this.element.addEventListener("turbo:before-morph-element", this.preserveInteractiveRegion)
    this.element.addEventListener("turbo:before-morph-attribute", this.preserveDisclosureState)
  }

  disconnect() {
    document.removeEventListener("turbo:before-fetch-response", this.noteFormResponse)
    document.removeEventListener("turbo:render", this.clearFormResponse)
    this.element.removeEventListener("turbo:before-morph-element", this.preserveInteractiveRegion)
    this.element.removeEventListener("turbo:before-morph-attribute", this.preserveDisclosureState)
  }

  noteFormResponse = (event) => {
    if (event.target instanceof HTMLFormElement && event.detail.fetchResponse.isHTML) {
      this.formResponsePending = true
    }
  }

  clearFormResponse = () => {
    this.formResponsePending = false
  }

  preserveInteractiveRegion = (event) => {
    // A same-page form redirect is rendered as a morph. It must be allowed to
    // replace the submitted page even when its submit button still has focus.
    if (this.formResponsePending) return

    const region = event.target
    if (!(region instanceof Element)) return

    if (this.regionHasActiveControl(region) || this.regionHasSelectedText(region) || this.regionHasProtectedForm(region)) {
      event.preventDefault()
    }
  }

  preserveDisclosureState = (event) => {
    if (this.formResponsePending) return

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
