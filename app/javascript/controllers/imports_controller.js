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

          if (!row) return;

          // Handle deletion complete - remove the row
          if (data.action === 'delete') {
            row.remove();
            return;
          }

          // Handle status and points updates
          const pointsCell = row.querySelector('[data-points-count]');
          if (pointsCell && data.import.points_count !== undefined) {
            pointsCell.textContent = new Intl.NumberFormat().format(data.import.points_count);
          }

          const statusCell = row.querySelector('[data-status-display]');
          if (statusCell && data.import.status) {
            statusCell.textContent = data.import.status;
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
