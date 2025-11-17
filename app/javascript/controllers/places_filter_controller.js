import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    console.log("Places filter controller connected");
  }

  filterPlaces(event) {
    // Get reference to the maps controller's placesManager
    const mapsController = window.mapsController;
    if (!mapsController || !mapsController.placesManager) {
      console.warn("Maps controller or placesManager not found");
      return;
    }

    // Collect all checked tag IDs
    const checkboxes = this.element.querySelectorAll('input[type="checkbox"][data-tag-id]');
    const selectedTagIds = Array.from(checkboxes)
      .filter(cb => cb.checked)
      .map(cb => parseInt(cb.dataset.tagId));

    console.log("Filtering places by tags:", selectedTagIds);

    // Filter places by selected tags (or show all if none selected)
    mapsController.placesManager.filterByTags(selectedTagIds.length > 0 ? selectedTagIds : null);
  }

  clearAll(event) {
    event.preventDefault();

    // Uncheck all checkboxes
    const checkboxes = this.element.querySelectorAll('input[type="checkbox"][data-tag-id]');
    checkboxes.forEach(cb => cb.checked = false);

    // Show all places
    const mapsController = window.mapsController;
    if (mapsController && mapsController.placesManager) {
      mapsController.placesManager.filterByTags(null);
    }
  }
}
