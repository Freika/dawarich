import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["checkbox", "durationContainer", "durationSelect", "expirationInfo"];
  static values = {
    memberId: Number,
    enabled: Boolean,
    familyId: Number,
    duration: String,
    expiresAt: String
  };

  connect() {
    console.log("Location sharing toggle controller connected");
    this.updateToggleState();
    this.setupExpirationTimer();
  }

  disconnect() {
    this.clearExpirationTimer();
  }

  toggle() {
    const newState = !this.enabledValue;
    const duration = this.hasDurationSelectTarget ? this.durationSelectTarget.value : 'permanent';

    // Optimistically update UI
    this.enabledValue = newState;
    this.updateToggleState();

    // Send the update to server
    this.updateLocationSharing(newState, duration);
  }

  changeDuration() {
    if (!this.enabledValue) return; // Only allow duration changes when sharing is enabled

    const duration = this.durationSelectTarget.value;
    this.durationValue = duration;

    // Update sharing with new duration
    this.updateLocationSharing(true, duration);
  }

  updateToggleState() {
    const isEnabled = this.enabledValue;

    // Update checkbox (DaisyUI toggle)
    this.checkboxTarget.checked = isEnabled;

    // Show/hide duration container
    if (this.hasDurationContainerTarget) {
      if (isEnabled) {
        this.durationContainerTarget.classList.remove('hidden');
      } else {
        this.durationContainerTarget.classList.add('hidden');
      }
    }
  }

  async updateLocationSharing(enabled, duration = 'permanent') {
    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute('content');

      const response = await fetch(`/family/update_location_sharing`, {
        method: 'PATCH',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify({
          enabled: enabled,
          duration: duration
        })
      });

      const data = await response.json();

      if (data.success) {
        // Update local values from server response
        this.durationValue = data.duration;
        this.expiresAtValue = data.expires_at;

        // Update duration select if it exists
        if (this.hasDurationSelectTarget) {
          this.durationSelectTarget.value = data.duration;
        }

        // Update expiration info
        this.updateExpirationInfo(data.expires_at_formatted);

        // Show success message
        this.showFlashMessage('success', data.message);

        // Setup/clear expiration timer
        this.setupExpirationTimer();

        // Trigger custom event for other controllers to listen to
        document.dispatchEvent(new CustomEvent('location-sharing:updated', {
          detail: {
            userId: this.memberIdValue,
            enabled: enabled,
            duration: data.duration,
            expiresAt: data.expires_at
          }
        }));
      } else {
        // Revert the UI change if server update failed
        this.enabledValue = !enabled;
        this.updateToggleState();
        this.showFlashMessage('error', data.message || 'Failed to update location sharing');
      }
    } catch (error) {
      console.error('Error updating location sharing:', error);

      // Revert the UI change if request failed
      this.enabledValue = !enabled;
      this.updateToggleState();
      this.showFlashMessage('error', 'Network error occurred while updating location sharing');
    }
  }

  setupExpirationTimer() {
    this.clearExpirationTimer();

    if (this.enabledValue && this.expiresAtValue) {
      const expiresAt = new Date(this.expiresAtValue);
      const now = new Date();
      const msUntilExpiration = expiresAt.getTime() - now.getTime();

      if (msUntilExpiration > 0) {
        // Set timer to automatically disable sharing when it expires
        this.expirationTimer = setTimeout(() => {
          this.enabledValue = false;
          this.updateToggleState();
          this.showFlashMessage('info', 'Location sharing has expired');

          // Trigger update event
          document.dispatchEvent(new CustomEvent('location-sharing:expired', {
            detail: { userId: this.memberIdValue }
          }));
        }, msUntilExpiration);

        // Also set up periodic updates to show countdown
        this.updateExpirationCountdown();
        this.countdownInterval = setInterval(() => {
          this.updateExpirationCountdown();
        }, 60000); // Update every minute
      }
    }
  }

  clearExpirationTimer() {
    if (this.expirationTimer) {
      clearTimeout(this.expirationTimer);
      this.expirationTimer = null;
    }
    if (this.countdownInterval) {
      clearInterval(this.countdownInterval);
      this.countdownInterval = null;
    }
  }

  updateExpirationInfo(formattedTime) {
    if (this.hasExpirationInfoTarget && formattedTime) {
      this.expirationInfoTarget.textContent = `Expires ${formattedTime}`;
      this.expirationInfoTarget.style.display = 'block';
    } else if (this.hasExpirationInfoTarget) {
      this.expirationInfoTarget.style.display = 'none';
    }
  }

  updateExpirationCountdown() {
    if (!this.hasExpirationInfoTarget || !this.expiresAtValue) return;

    const expiresAt = new Date(this.expiresAtValue);
    const now = new Date();
    const msUntilExpiration = expiresAt.getTime() - now.getTime();

    if (msUntilExpiration <= 0) {
      this.expirationInfoTarget.textContent = 'Expired';
      this.expirationInfoTarget.style.display = 'block';
      return;
    }

    const hoursLeft = Math.floor(msUntilExpiration / (1000 * 60 * 60));
    const minutesLeft = Math.floor((msUntilExpiration % (1000 * 60 * 60)) / (1000 * 60));

    let timeText;
    if (hoursLeft > 0) {
      timeText = `${hoursLeft}h ${minutesLeft}m remaining`;
    } else {
      timeText = `${minutesLeft}m remaining`;
    }

    this.expirationInfoTarget.textContent = `Expires in ${timeText}`;
  }

  showFlashMessage(type, message) {
    // Create a flash message element matching the project style (_flash.html.erb)
    const flashContainer = document.getElementById('flash-messages') ||
                          this.createFlashContainer();

    const bgClass = this.getFlashClasses(type);

    const flashElement = document.createElement('div');
    flashElement.className = `flex items-center ${bgClass} py-3 px-5 rounded-lg z-[6000]`;
    flashElement.innerHTML = `
      <div class="mr-4">${message}</div>
      <button type="button">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    `;

    // Add click handler to dismiss button
    const dismissButton = flashElement.querySelector('button');
    dismissButton.addEventListener('click', () => {
      flashElement.classList.add('fade-out');
      setTimeout(() => {
        flashElement.remove();
        // Remove the container if it's empty
        if (flashContainer && !flashContainer.hasChildNodes()) {
          flashContainer.remove();
        }
      }, 150);
    });

    flashContainer.appendChild(flashElement);

    // Auto-remove after 5 seconds
    setTimeout(() => {
      if (flashElement.parentNode) {
        flashElement.classList.add('fade-out');
        setTimeout(() => {
          flashElement.remove();
          // Remove the container if it's empty
          if (flashContainer && !flashContainer.hasChildNodes()) {
            flashContainer.remove();
          }
        }, 150);
      }
    }, 5000);
  }

  createFlashContainer() {
    const container = document.createElement('div');
    container.id = 'flash-messages';
    container.className = 'fixed top-5 right-5 flex flex-col gap-2 z-50';
    document.body.appendChild(container);
    return container;
  }

  getFlashClasses(type) {
    switch (type) {
      case 'error':
      case 'alert':
        return 'bg-red-100 text-red-700 border-red-300';
      default:
        return 'bg-blue-100 text-blue-700 border-blue-300';
    }
  }

  // Helper method to check if user's own location sharing is enabled
  // This can be used by other controllers
  static getUserLocationSharingStatus() {
    const toggleController = document.querySelector('[data-controller*="location-sharing-toggle"]');
    if (toggleController) {
      const controller = this.application.getControllerForElementAndIdentifier(toggleController, 'location-sharing-toggle');
      return controller?.enabledValue || false;
    }
    return false;
  }
}
