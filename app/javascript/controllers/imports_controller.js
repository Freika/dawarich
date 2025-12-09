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

            const statusCell = row.querySelector('[data-status-display]');
            if (statusCell && data.import.status) {
              statusCell.innerHTML = this.renderStatusBadge(data.import.status);
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

  renderStatusBadge(status) {
    const statusLower = status.toLowerCase();

    switch(statusLower) {
      case 'completed':
        return `<span class="badge badge-success badge-sm gap-1">
                  <span class="text-xs">✓</span>
                  <span>Completed</span>
                </span>`;
      case 'processing':
        return `<span class="badge badge-warning badge-sm gap-1">
                  <span class="loading loading-spinner loading-xs"></span>
                  <span>Processing</span>
                </span>`;
      case 'failed':
        return `<span class="badge badge-error badge-sm gap-1">
                  <span class="text-xs">✕</span>
                  <span>Failed</span>
                </span>`;
      default:
        return `<span class="badge badge-sm">${this.capitalize(status)}</span>`;
    }
  }

  capitalize(str) {
    return str.charAt(0).toUpperCase() + str.slice(1);
  }
}
