import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "prefixList",
    "shopList",
    "prefixInput",
    "globalStatus",
    "prefixMode",
    "toast",
    "prefixEmpty",
    "refreshButton",
    "enableGlobalButton",
    "disableGlobalButton",
    "allowAllButton",
    "allowlistButton",
    "addPrefixButton",
  ];

  connect() {
    this.state = {
      global_enabled: false,
      prefix_mode: "allowlist",
      rollout_prefixes: [],
      shops: [],
    };
    this.loading = false;
    this.refresh();
  }

  async refresh() {
    await this.withLoading(
      async () => {
        const res = await fetch("/ops/stock_sync_rollout", {
          headers: { Accept: "application/json" },
        });

        const data = await this.parseJsonResponse(
          res,
          "refresh /ops/stock_sync_rollout",
        );

        if (!res.ok || !data.ok) {
          throw new Error(data.error || "Failed to load rollout state");
        }

        this.state = data.rollout || {};
        this.render();
      },
      { silent: true },
    );
  }

  render() {
    this.renderGlobal();
    this.renderPrefixMode();
    this.renderPrefixes();
    this.renderShops();
    this.renderActionStates();
  }

  renderGlobal() {
    const enabled = Boolean(this.state.global_enabled);

    this.globalStatusTarget.textContent = enabled ? "ENABLED" : "DISABLED";
    this.globalStatusTarget.className = `stock-sync-badge ${enabled ? "stock-sync-badge--green" : "stock-sync-badge--gray"}`;
  }

  renderPrefixMode() {
    const mode = this.state.prefix_mode === "all" ? "all" : "allowlist";

    this.prefixModeTarget.textContent =
      mode === "all" ? "ALL SKUS" : "ALLOWLIST";
    this.prefixModeTarget.className = `stock-sync-badge ${mode === "all" ? "stock-sync-badge--green" : "stock-sync-badge--blue"}`;
  }

  renderPrefixes() {
    const list = Array.isArray(this.state.rollout_prefixes)
      ? this.state.rollout_prefixes
      : [];

    if (list.length === 0) {
      this.prefixListTarget.innerHTML = "";
      this.prefixEmptyTarget.classList.remove("hidden");
      return;
    }

    this.prefixEmptyTarget.classList.add("hidden");

    this.prefixListTarget.innerHTML = list
      .map(
        (prefix) => `
          <div class="stock-sync-chip">
            <span class="stock-sync-chip__text">${this.escapeHtml(prefix)}</span>
            <button
              type="button"
              class="stock-sync-chip__remove"
              data-prefix="${this.escapeAttribute(prefix)}"
              data-action="click->stock-sync#removePrefix"
              aria-label="Remove ${this.escapeAttribute(prefix)}"
              ${this.loading ? "disabled" : ""}>
              ×
            </button>
          </div>
        `,
      )
      .join("");
  }

  renderShops() {
    const shops = Array.isArray(this.state.shops) ? this.state.shops : [];

    this.shopListTarget.innerHTML = shops
      .map((shop) => {
        const enabled = Boolean(shop.stock_sync_enabled);
        const active = Boolean(shop.active);
        const badgeClass = enabled
          ? "stock-sync-badge--green"
          : "stock-sync-badge--gray";
        const badgeText = enabled ? "ON" : "OFF";
        const activeClass = active
          ? "stock-sync-shop-card__meta--active"
          : "stock-sync-shop-card__meta--inactive";
        const activeText = active ? "Active" : "Inactive";

        const enableDisabled = this.loading || !active || enabled;
        const disableDisabled = this.loading || !enabled;
        const backfillDisabled = this.loading || !active || !enabled;

        return `
          <article class="stock-sync-shop-card ${!active ? "is-inactive" : ""}">
            <div class="stock-sync-shop-card__header">
              <div>
                <div class="stock-sync-shop-card__title">${this.escapeHtml(shop.shop_code)}</div>
                <div class="stock-sync-shop-card__channel">${this.escapeHtml(shop.channel)}</div>
              </div>

              <div class="stock-sync-badge ${badgeClass}">
                ${badgeText}
              </div>
            </div>

            <div class="stock-sync-shop-card__meta-row">
              <span class="stock-sync-shop-card__meta ${activeClass}">${activeText}</span>
              <span class="stock-sync-shop-card__meta">Fail ${Number(shop.sync_fail_count || 0)}</span>
            </div>

            ${
              shop.last_sync_error
                ? `
                  <div class="stock-sync-shop-card__error">
                    ${this.escapeHtml(shop.last_sync_error)}
                  </div>
                `
                : `
                  <div class="stock-sync-shop-card__hint">
                    ${shop.last_sync_failed_at ? this.escapeHtml(String(shop.last_sync_failed_at)) : "No recent sync errors"}
                  </div>
                `
            }

            <div class="stock-sync-shop-card__actions">
              <button
                type="button"
                class="btn btn-secondary"
                data-id="${shop.id}"
                data-action="click->stock-sync#enableShop"
                ${enableDisabled ? "disabled" : ""}>
                Enable
              </button>

              <button
                type="button"
                class="btn btn-secondary"
                data-id="${shop.id}"
                data-action="click->stock-sync#disableShop"
                ${disableDisabled ? "disabled" : ""}>
                Disable
              </button>

              <button
                type="button"
                class="btn btn-primary"
                data-id="${shop.id}"
                data-shop-code="${this.escapeAttribute(shop.shop_code)}"
                data-action="click->stock-sync#backfill"
                ${backfillDisabled ? "disabled" : ""}>
                Backfill
              </button>
            </div>
          </article>
        `;
      })
      .join("");
  }

  renderActionStates() {
    const globalEnabled = Boolean(this.state.global_enabled);
    const prefixMode = this.state.prefix_mode === "all" ? "all" : "allowlist";

    if (this.hasEnableGlobalButtonTarget) {
      this.enableGlobalButtonTarget.disabled = this.loading || globalEnabled;
    }

    if (this.hasDisableGlobalButtonTarget) {
      this.disableGlobalButtonTarget.disabled = this.loading || !globalEnabled;
    }

    if (this.hasAllowAllButtonTarget) {
      this.allowAllButtonTarget.disabled = this.loading || prefixMode === "all";
    }

    if (this.hasAllowlistButtonTarget) {
      this.allowlistButtonTarget.disabled =
        this.loading || prefixMode === "allowlist";
    }

    if (this.hasAddPrefixButtonTarget) {
      this.addPrefixButtonTarget.disabled = this.loading;
    }

    if (this.hasRefreshButtonTarget) {
      this.refreshButtonTarget.disabled = this.loading;
    }

    if (this.hasPrefixInputTarget) {
      this.prefixInputTarget.disabled = this.loading;
    }
  }

  async enableGlobal() {
    await this.updateGlobal(true);
  }

  async disableGlobal() {
    await this.updateGlobal(false);
  }

  async updateGlobal(enabled) {
    await this.withLoading(async () => {
      const res = await fetch(
        `/ops/stock_sync_rollout/global?enabled=${enabled}`,
        {
          method: "PATCH",
          headers: { Accept: "application/json" },
        },
      );

      const data = await this.parseJsonResponse(
        res,
        "updateGlobal /ops/stock_sync_rollout/global",
      );

      if (!res.ok || !data.ok) {
        throw new Error(data.error || "Failed to update global setting");
      }

      this.showToast(
        enabled ? "Global sync enabled" : "Global sync disabled",
        "success",
      );
      await this.refresh();
    });
  }

  async setAll() {
    await this.updatePrefixMode("all");
  }

  async setAllowlist() {
    await this.updatePrefixMode("allowlist");
  }

  async updatePrefixMode(mode) {
    await this.withLoading(async () => {
      const res = await fetch(
        `/ops/stock_sync_rollout/prefix_mode?mode=${encodeURIComponent(mode)}`,
        {
          method: "PATCH",
          headers: { Accept: "application/json" },
        },
      );

      const data = await this.parseJsonResponse(
        res,
        "updatePrefixMode /ops/stock_sync_rollout/prefix_mode",
      );

      if (!res.ok || !data.ok) {
        throw new Error(data.error || "Failed to update prefix mode");
      }

      this.showToast(
        mode === "all"
          ? "Prefix mode set to Allow All"
          : "Prefix mode set to Allowlist",
        "success",
      );
      await this.refresh();
    });
  }

  onPrefixKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      this.addPrefix();
    }
  }

  async addPrefix() {
    const value = this.prefixInputTarget.value.trim();
    if (!value) return;

    const current = Array.isArray(this.state.rollout_prefixes)
      ? this.state.rollout_prefixes
      : [];

    if (current.includes(value)) {
      this.showToast("Prefix already exists", "warning");
      return;
    }

    const updated = [...current, value];

    await this.savePrefixList(updated, `Added prefix: ${value}`);
    this.prefixInputTarget.value = "";
  }

  async removePrefix(event) {
    const prefix = event.currentTarget.dataset.prefix;
    const current = Array.isArray(this.state.rollout_prefixes)
      ? this.state.rollout_prefixes
      : [];
    const updated = current.filter((item) => item !== prefix);

    await this.savePrefixList(updated, `Removed prefix: ${prefix}`);
  }

  async savePrefixList(prefixes, successMessage) {
    await this.withLoading(async () => {
      const res = await fetch("/ops/stock_sync_rollout/prefix_list", {
        method: "PATCH",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ prefixes }),
      });

      const data = await this.parseJsonResponse(
        res,
        "savePrefixList /ops/stock_sync_rollout/prefix_list",
      );

      if (!res.ok || !data.ok) {
        throw new Error(data.error || "Failed to update prefix list");
      }

      this.showToast(successMessage, "success");
      await this.refresh();
    });
  }

  async enableShop(event) {
    const id = event.currentTarget.dataset.id;
    await this.updateShop(id, true);
  }

  async disableShop(event) {
    const id = event.currentTarget.dataset.id;
    await this.updateShop(id, false);
  }

  async updateShop(id, enabled) {
    await this.withLoading(async () => {
      const res = await fetch(
        `/ops/stock_sync_rollout_shops/${id}/toggle?enabled=${enabled}`,
        {
          method: "PATCH",
          headers: { Accept: "application/json" },
        },
      );

      const data = await this.parseJsonResponse(
        res,
        "updateShop /ops/stock_sync_rollout_shops/toggle",
      );

      if (!res.ok || !data.ok) {
        throw new Error(data.error || "Failed to update shop setting");
      }

      this.showToast(
        enabled ? "Shop sync enabled" : "Shop sync disabled",
        "success",
      );
      await this.refresh();
    });
  }

  async backfill(event) {
    const id = event.currentTarget.dataset.id;
    const shopCode = event.currentTarget.dataset.shopCode || "this shop";

    const ok = window.confirm(`Run backfill for ${shopCode}?`);
    if (!ok) return;

    await this.withLoading(async () => {
      const res = await fetch(`/ops/stock_sync_rollout_shops/${id}/backfill`, {
        method: "POST",
        headers: { Accept: "application/json" },
      });

      const data = await this.parseJsonResponse(
        res,
        "backfill /ops/stock_sync_rollout_shops/backfill",
      );

      if (!res.ok || !data.ok) {
        throw new Error(data.error || "Failed to trigger backfill");
      }

      this.showToast(`Backfill started for ${shopCode}`, "success");
      await this.refresh();
    });
  }

  async withLoading(fn, options = {}) {
    const silent = Boolean(options.silent);

    try {
      this.loading = true;
      this.render();
      if (!silent) this.showToast("Processing...", "info");

      await fn();
    } catch (error) {
      console.error("stock-sync error", error);
      this.showToast(error.message || "Something went wrong", "error");
    } finally {
      this.loading = false;
      this.render();
    }
  }

  showToast(message, variant = "info") {
    if (!this.hasToastTarget) return;

    this.toastTarget.textContent = message;
    this.toastTarget.className = `stock-sync-toast stock-sync-toast--${variant}`;
    this.toastTarget.classList.remove("hidden");

    clearTimeout(this.toastTimer);
    this.toastTimer = setTimeout(() => {
      this.toastTarget.classList.add("hidden");
    }, 2200);
  }

  async parseJsonResponse(response, context = "request") {
    const contentType = response.headers.get("content-type") || "";

    if (contentType.includes("application/json")) {
      return await response.json();
    }

    const text = await response.text();

    console.error(`${context} returned non-JSON response`, {
      status: response.status,
      contentType,
      body: text.slice(0, 1000),
    });

    throw new Error(
      `Expected JSON response but got ${contentType || "unknown content type"} (status ${response.status})`,
    );
  }

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  escapeAttribute(value) {
    return this.escapeHtml(value);
  }
}
