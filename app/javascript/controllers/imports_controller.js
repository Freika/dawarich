import BaseController from "./base_controller"

// Import progress is now handled via Turbo Stream broadcasts.
// This controller is retained as a no-op for existing data-controller="imports" attributes.
export default class extends BaseController {}
