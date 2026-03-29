import { Controller } from "@hotwired/stimulus";

// Same as rules_controller but without action templates (notification rules have no THEN section)
export default class extends Controller {
  static targets = [
    "conditionTemplate",
    "conditionGroupTemplate",
    "conditionsList",
    "effectiveDateInput",
    "frequencyWrap",
    "minimumAmountWrap",
    "scheduleAnchorWrap",
    "scheduleHourWrap",
    "scheduleDowWrap",
  ];

  connect() {
    this.updateConditionPrefixes();
    this.#syncFrequencyFieldVisibility();
  }

  addConditionGroup() {
    this.#appendTemplate(
      this.conditionGroupTemplateTarget,
      this.conditionsListTarget,
    );
    this.updateConditionPrefixes();
  }

  addCondition() {
    this.#appendTemplate(
      this.conditionTemplateTarget,
      this.conditionsListTarget,
    );
    this.updateConditionPrefixes();
  }

  clearEffectiveDate() {
    this.effectiveDateInputTarget.value = "";
  }

  deliveryChanged(event) {
    this.#setFrequencyWrapVisible(event.target.value === "scheduled");
    this.#syncScheduleFieldsVisibility();
  }

  frequencyChanged() {
    this.#syncScheduleFieldsVisibility();
  }

  #syncFrequencyFieldVisibility() {
    const deliverySelect = this.element.querySelector(
      'select[name*="[delivery]"]',
    );
    if (!deliverySelect || !this.hasFrequencyWrapTarget) return;

    this.#setFrequencyWrapVisible(deliverySelect.value === "scheduled");
    this.#syncScheduleFieldsVisibility();
  }

  #setFrequencyWrapVisible(show) {
    if (!this.hasFrequencyWrapTarget) return;

    this.frequencyWrapTarget.classList.toggle("hidden", !show);
    if (!show) {
      const freqSelect = this.frequencyWrapTarget.querySelector(
        'select[name*="[frequency]"]',
      );
      if (freqSelect) {
        freqSelect.selectedIndex = 0;
      }
    }
  }

  #syncScheduleFieldsVisibility() {
    if (!this.hasScheduleAnchorWrapTarget) return;

    const deliverySelect = this.element.querySelector(
      'select[name*="[delivery]"]',
    );
    const scheduled = deliverySelect?.value === "scheduled";
    const freqSelect = this.frequencyWrapTarget?.querySelector(
      'select[name*="[frequency]"]',
    );
    const frequency = freqSelect?.value ?? "";
    const showAnchor =
      scheduled && (frequency === "daily" || frequency === "weekly");

    this.scheduleAnchorWrapTarget.classList.toggle("hidden", !showAnchor);
    if (this.hasScheduleHourWrapTarget) {
      this.scheduleHourWrapTarget.classList.toggle("hidden", !showAnchor);
    }
    if (this.hasScheduleDowWrapTarget) {
      this.scheduleDowWrapTarget.classList.toggle(
        "hidden",
        !showAnchor || frequency !== "weekly",
      );
    }
  }

  #appendTemplate(templateEl, listEl) {
    const html = templateEl.innerHTML.replaceAll(
      "IDX_PLACEHOLDER",
      this.#uniqueKey(),
    );

    listEl.insertAdjacentHTML("beforeend", html);
  }

  #uniqueKey() {
    return Date.now();
  }

  updateConditionPrefixes() {
    const conditions = Array.from(this.conditionsListTarget.children);
    let conditionIndex = 0;

    conditions.forEach((condition) => {
      if (!condition.classList.contains("hidden")) {
        const prefixEl = condition.querySelector("[data-condition-prefix]");
        if (prefixEl) {
          if (conditionIndex === 0) {
            prefixEl.classList.add("hidden");
          } else {
            prefixEl.classList.remove("hidden");
          }
          conditionIndex++;
        }
      }
    });
  }
}
