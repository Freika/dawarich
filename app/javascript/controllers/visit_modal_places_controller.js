import { Controller } from "@hotwired/stimulus";

export default class extends Controller {

  connect() {
    this.visitId = this.element.dataset.id;
    this.apiKey = this.element.dataset.api_key;
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
}
