// This controller is being used on:
// - trips/new
// - trips/edit

import BaseController from "./base_controller"

export default class extends BaseController {
  static targets = ["startedAt", "endedAt", "apiKey"]
  static values = { tripsId: String }

  connect() {
    console.log("Datetime controller connected")
    this.debounceTimer = null;
  }

  async updateCoordinates(event) {
    // Clear any existing timeout
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
    }

    // Set new timeout
    this.debounceTimer = setTimeout(async () => {
      const startedAt = this.startedAtTarget.value
      const endedAt = this.endedAtTarget.value
      const apiKey = this.apiKeyTarget.value

      if (startedAt && endedAt) {
        try {
          const params = new URLSearchParams({
            start_at: startedAt,
            end_at: endedAt,
            api_key: apiKey,
            slim: true
          })
          let allPoints = [];
          let currentPage = 1;
          const perPage = 1000;

          do {
            const paginatedParams = `${params}&page=${currentPage}&per_page=${perPage}`;
            const response = await fetch(`/api/v1/points?${paginatedParams}`);
            const data = await response.json();

            allPoints = [...allPoints, ...data];

            const totalPages = parseInt(response.headers.get('X-Total-Pages'));
            currentPage++;

            if (!totalPages || currentPage > totalPages) {
              break;
            }
          } while (true);

          const event = new CustomEvent('coordinates-updated', {
            detail: { coordinates: allPoints },
            bubbles: true,
            composed: true
          })

          const tripsElement = document.querySelector('[data-controller="trips"]')
          if (tripsElement) {
            tripsElement.dispatchEvent(event)
          } else {
            console.error('Trips controller element not found')
          }
        } catch (error) {
          console.error('Error:', error)
        }
      }
    }, 500);
  }
}
