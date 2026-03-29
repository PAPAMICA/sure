import { Controller } from "@hotwired/stimulus";

// Quick categorize: search/filter categories, Enter picks first match, debounced autosave for text fields.
// Category rows use [data-qc-category] so filtering does not rely on Stimulus multi-target registration.
export default class extends Controller {
  static targets = ["search", "name", "notes"];
  static values = {
    autosaveUrl: String,
    transactionId: String,
  };

  connect() {
    if (this.hasSearchTarget) {
      requestAnimationFrame(() => {
        try {
          this.searchTarget.focus();
        } catch (_) {
          /* ignore */
        }
      });
    }
    this.filter();
  }

  filter() {
    const q = this.normalizeForSearch(this.searchTarget?.value || "");
    this.categoryRowElements.forEach((row) => {
      const raw = row.getAttribute("data-qc-category") || "";
      const name = this.normalizeForSearch(raw);
      const show = q.length === 0 || name.includes(q);
      row.classList.toggle("hidden", !show);
    });
  }

  normalizeForSearch(str) {
    return str
      .toLowerCase()
      .trim()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "");
  }

  searchKeydown(event) {
    if (event.key !== "Enter") return;
    event.preventDefault();
    this.pickFirstVisibleCategory();
  }

  get categoryRowElements() {
    return Array.from(this.element.querySelectorAll("[data-qc-category]"));
  }

  pickFirstVisibleCategory() {
    const row = this.categoryRowElements.find((r) => !r.classList.contains("hidden"));
    if (!row) return;
    const btn =
      row.querySelector("button[type='submit']") ||
      row.querySelector("input[type='submit']");
    btn?.click();
  }

  scheduleSave() {
    if (!this.autosaveUrlValue) return;
    clearTimeout(this._saveTimer);
    this._saveTimer = setTimeout(() => this.saveFields(), 450);
  }

  async saveFields() {
    if (!this.autosaveUrlValue) return;
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    if (!token) return;

    const body = new FormData();
    body.append("authenticity_token", token);
    body.append("quick_categorize", "1");
    body.append("quick_categorize_autosave", "1");
    body.append("entry[entryable_type]", "Transaction");
    body.append("entry[entryable_attributes][id]", this.transactionIdValue);
    if (this.hasNameTarget) body.append("entry[name]", this.nameTarget.value);
    if (this.hasNotesTarget) body.append("entry[notes]", this.notesTarget.value);

    try {
      await fetch(this.autosaveUrlValue, {
        method: "PATCH",
        body,
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": token,
        },
        credentials: "same-origin",
      });
    } catch (_) {
      /* ignore network errors for background save */
    }
  }
}
