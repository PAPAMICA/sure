import { Controller } from "@hotwired/stimulus";

// Quick categorize: search/filter categories, Enter picks first match, debounced autosave for text fields.
export default class extends Controller {
  static targets = ["search", "categoryRow", "name", "notes"];
  static values = {
    autosaveUrl: String,
    transactionId: String,
  };

  connect() {
    if (this.hasSearchTarget) {
      requestAnimationFrame(() => this.searchTarget.focus());
    }
    this.filter();
  }

  filter() {
    const q = (this.searchTarget?.value || "").toLowerCase().trim();
    this.categoryRowTargets.forEach((row) => {
      const name = (row.dataset.categoryName || "").toLowerCase();
      const show = q === "" || name.includes(q);
      row.classList.toggle("hidden", !show);
    });
  }

  searchKeydown(event) {
    if (event.key !== "Enter") return;
    event.preventDefault();
    this.pickFirstVisibleCategory();
  }

  pickFirstVisibleCategory() {
    const row = this.categoryRowTargets.find((r) => !r.classList.contains("hidden"));
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
