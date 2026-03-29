import { Controller } from "@hotwired/stimulus";

// Quick categorize: live filter reorders the DOM (matches first), Enter picks first visible, debounced autosave.
export default class extends Controller {
  static targets = ["search", "name", "notes", "categoryList", "emptyState", "resultMeta"];
  static values = {
    autosaveUrl: String,
    transactionId: String,
    allCategoriesText: String,
    resultsCountText: String,
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
    this._filterScheduled = false;
    this.filter();
  }

  scheduleFilter() {
    if (this._filterScheduled) return;
    this._filterScheduled = true;
    requestAnimationFrame(() => {
      this._filterScheduled = false;
      this.filter();
    });
  }

  filter() {
    if (!this.hasCategoryListTarget) return;

    const q = this.normalizeForSearch(this.searchTarget?.value || "");
    const container = this.categoryListTarget;
    const emptyEl = this.hasEmptyStateTarget ? this.emptyStateTarget : null;
    const items = [...container.querySelectorAll("[data-qc-category]")];

    const withMeta = items.map((el) => {
      const raw = el.getAttribute("data-qc-category") || "";
      const norm = this.normalizeForSearch(raw);
      const match = q.length === 0 || norm.includes(q);
      const sort = parseInt(el.getAttribute("data-qc-sort") || "0", 10);
      return { el, match, sort };
    });

    const matching = withMeta.filter((x) => x.match).sort((a, b) => a.sort - b.sort);
    const notMatching = withMeta.filter((x) => !x.match).sort((a, b) => a.sort - b.sort);

    if (q.length > 0 && matching.length === 0) {
      emptyEl?.classList.remove("hidden");
      items.forEach((el) => el.classList.add("hidden"));
      if (emptyEl) {
        container.replaceChildren(emptyEl, ...items);
      }
      this.updateResultMeta(q, items.length, 0);
      return;
    }

    emptyEl?.classList.add("hidden");
    for (const { el } of matching) {
      el.classList.remove("hidden");
    }
    for (const { el } of notMatching) {
      if (q.length > 0) {
        el.classList.add("hidden");
      } else {
        el.classList.remove("hidden");
      }
    }

    const ordered = [];
    if (emptyEl) {
      ordered.push(emptyEl);
    }
    ordered.push(
      ...matching.map((x) => x.el),
      ...notMatching.map((x) => x.el),
    );
    container.replaceChildren(...ordered);

    this.updateResultMeta(q, items.length, matching.length);
  }

  updateResultMeta(query, total, matchCount) {
    if (!this.hasResultMetaTarget) return;
    const el = this.resultMetaTarget;
    if (query.length === 0) {
      el.textContent = this.allCategoriesTextValue;
    } else if (matchCount === 0) {
      el.textContent = "";
    } else {
      el.textContent = this.resultsCountTextValue
        .replace("%{count}", String(matchCount))
        .replace("%{total}", String(total));
    }
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

  pickFirstVisibleCategory() {
    if (!this.hasCategoryListTarget) return;
    const row = [...this.categoryListTarget.querySelectorAll("[data-qc-category]")].find(
      (r) => !r.classList.contains("hidden"),
    );
    if (!row) return;
    const btn =
      row.querySelector("button[type='submit']") || row.querySelector("input[type='submit']");
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
