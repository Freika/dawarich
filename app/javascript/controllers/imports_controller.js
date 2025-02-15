import BaseController from "./base_controller";
import consumer from "../channels/consumer";

export default class extends BaseController {
  static targets = ["index"];

  connect() {
    if (!this.hasIndexTarget) {
      console.log("No index target found, skipping subscription")
      return
    }

    this.setupSubscription();
  }

  setupSubscription() {
    const userId = this.element.dataset.userId;

    this.channel = consumer.subscriptions.create(
      { channel: "ImportsChannel" },
      {
        connected: () => {
        },
        disconnected: () => {
        },
        received: (data) => {
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
