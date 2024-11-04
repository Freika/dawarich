import { Controller } from "@hotwired/stimulus";
import consumer from "../channels/consumer";

export default class extends Controller {
  static targets = ["index"];

  connect() {
    console.log("Imports controller connected", {
      hasIndexTarget: this.hasIndexTarget,
      element: this.element,
      userId: this.element.dataset.userId
    });
    this.setupSubscription();
  }

  setupSubscription() {
    const userId = this.element.dataset.userId;
    console.log("Setting up subscription with userId:", userId);

    this.channel = consumer.subscriptions.create(
      { channel: "ImportsChannel" },
      {
        connected: () => {
          console.log("Successfully connected to ImportsChannel");
          // Test that we can receive messages
          console.log("Subscription object:", this.channel);
        },
        disconnected: () => {
          console.log("Disconnected from ImportsChannel");
        },
        received: (data) => {
          console.log("Received data:", data);
          const row = this.element.querySelector(`tr[data-import-id="${data.import.id}"]`);

          if (row) {
            const pointsCell = row.querySelector('[data-points-count]');
            if (pointsCell) {
              pointsCell.textContent = new Intl.NumberFormat().format(data.import.points_count);
            }
          }
        }
      }
    );
  }

  disconnect() {
    if (this.channel) {
      this.channel.unsubscribe();
    }
  }
}
