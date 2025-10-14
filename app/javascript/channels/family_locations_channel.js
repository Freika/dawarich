import consumer from "./consumer"

// Only create subscription if family feature is enabled
const familyFeaturesElement = document.querySelector('[data-family-members-features-value]');
const features = familyFeaturesElement ? JSON.parse(familyFeaturesElement.dataset.familyMembersFeaturesValue) : {};

if (features.family) {
  consumer.subscriptions.create("FamilyLocationsChannel", {
    connected() {
      // Connected to family locations channel
    },

    disconnected() {
      // Disconnected from family locations channel
    },

    received(data) {
      // Pass data to family members controller if it exists
      if (window.familyMembersController) {
        window.familyMembersController.updateSingleMemberLocation(data);
      }
    }
  });
}
