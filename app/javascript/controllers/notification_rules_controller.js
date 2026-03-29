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
  ];

  connect() {
    this.updateConditionPrefixes();
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
    const show = event.target.value === "scheduled";
    if (this.hasFrequencyWrapTarget) {
      this.frequencyWrapTarget.classList.toggle("hidden", !show);
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
