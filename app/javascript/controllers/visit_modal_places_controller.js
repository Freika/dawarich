import BaseController from "./base_controller"

export default class extends BaseController {
  static targets = ["name", "input"]

  connect() {
    this.apiKey = this.element.dataset.api_key;
    this.visitId = this.element.dataset.id;

    this.element.addEventListener("visit-name:updated", this.updateAll.bind(this));
  }

  // Action to handle selection change
  selectPlace(event) {
    const selectedPlaceId = event.target.value; // Get the selected place ID

    // Send PATCH request to update the place for the visit
    this.updateVisitPlace(selectedPlaceId);
  }

  updateVisitPlace(placeId) {
    const url = `/api/v1/visits/${this.visitId}?api_key=${this.apiKey}`;

    fetch(url, {
      method: 'PATCH',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({ place_id: placeId })
    })
    .then(response => {
      if (!response.ok) {
        throw new Error('Network response was not ok');
      }
      return response.json();
    })
    .then(data => {
      console.log('Success:', data);
      this.updateVisitNameOnPage(data.name);
    })
    .catch((error) => {
      console.error('Error:', error);
    });
  }

  updateVisitNameOnPage(newName) {
    document.querySelectorAll(`[data-visit-name="${this.visitId}"]`).forEach(element => {
      element.textContent = newName;
    });
  }

  updateAll(event) {
    const newName = event.detail.name;
    this.updateVisitNameOnPage(newName);
  }
}
