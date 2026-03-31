import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["centerLabel", "centerValue", "barTooltip"];
  static values = {
    defaultLabel: String,
    defaultValue: String,
  };

  connect() {
    this.resetCenter();
    this.hideBarTooltip();
  }

  preview(event) {
    const el = event.currentTarget;
    const name = el.dataset.liquidityName;
    const amount = el.dataset.liquidityAmount;
    if (!name || !amount) return;

    this.centerLabelTarget.textContent = name;
    this.centerValueTarget.textContent = amount;
  }

  clearPreview() {
    this.resetCenter();
  }

  showBarTooltip(event) {
    const el = event.currentTarget;
    const name = el.dataset.liquidityName;
    const amount = el.dataset.liquidityAmount;
    const weight = el.dataset.liquidityWeight;
    if (!name || !amount) return;

    this.barTooltipTarget.textContent = weight ? `${name} — ${amount} (${weight})` : `${name} — ${amount}`;
    this.barTooltipTarget.classList.remove("hidden");
  }

  hideBarTooltip() {
    this.barTooltipTarget.classList.add("hidden");
  }

  resetCenter() {
    this.centerLabelTarget.textContent = this.defaultLabelValue;
    this.centerValueTarget.textContent = this.defaultValueValue;
  }
}

