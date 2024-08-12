// app/javascript/controllers/visit_name_controller.js

import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["name", "input"];

  connect() {
    this.apiKey = this.element.dataset.api_key;
    this.visitId = this.element.dataset.id;

    // Listen for custom event to update all instances
    this.element.addEventListener("visit-name:updated", this.updateAll.bind(this));
  }

  edit() {
    this.nameTargets.forEach((nameTarget, index) => {
      nameTarget.classList.add("hidden");
      this.inputTargets[index].classList.remove("hidden");
      this.inputTargets[index].focus();
    });
  }

  save() {
    const newName = this.inputTargets[0].value; // Assuming both inputs have the same value

    fetch(`/api/v1/visits/${this.visitId}?api_key=${this.apiKey}`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ visit: { name: newName } })
    })
    .then(response => {
      if (response.ok) {
        this.updateAllInstances(newName);
      } else {
        return response.json().then(errors => Promise.reject(errors));
      }
    })
    .catch(() => {
      alert("Error updating visit name.");
    });
  }

  updateAllInstances(newName) {
    // Dispatch a custom event that other instances of this controller can listen to
    const event = new CustomEvent("visit-name:updated", { detail: { newName } });
    document.querySelectorAll(`[data-id="${this.visitId}"]`).forEach(element => {
      element.dispatchEvent(event);
    });
  }

  updateAll(event) {
    const newName = event.detail.newName;

    // Update all name displays
    this.nameTargets.forEach(nameTarget => {
      nameTarget.textContent = newName;
      nameTarget.classList.remove("hidden");
    });

    // Update all input fields
    this.inputTargets.forEach(inputTarget => {
      inputTarget.value = newName;
      inputTarget.classList.add("hidden");
    });
  }

  cancel() {
    this.nameTargets.forEach((nameTarget, index) => {
      nameTarget.classList.remove("hidden");
      this.inputTargets[index].classList.add("hidden");
    });
  }

  handleEnter(event) {
    if (event.key === "Enter") {
      this.save();
    } else if (event.key === "Escape") {
      this.cancel();
    }
  }
}
