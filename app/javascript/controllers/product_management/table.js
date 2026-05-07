export const productManagementTableMethods = {
  applyFrontendFilters(skus) {
    const items = Array.isArray(skus) ? skus : [];
    const mode = this.hasRiskFilterSelectTarget
      ? this.riskFilterSelectTarget.value
      : "all";

    if (mode === "frozen") {
      return items.filter((sku) => sku.frozen);
    }

    if (mode === "zero_online") {
      return items.filter((sku) => Number(sku.online_available || 0) === 0);
    }

    if (mode === "risky") {
      return items.filter((sku) => this.isRiskySku(sku));
    }

    return items;
  },

  isRiskySku(sku) {
    const onHand = Number(sku.on_hand || 0);
    const reserved = Number(sku.reserved || 0);
    const storeAvailable = Number(sku.store_available || 0);
    const onlineAvailable = Number(sku.online_available || 0);
    const buffer = Number(sku.buffer_quantity || 0);

    return (
      Boolean(sku.frozen) ||
      reserved > onHand ||
      (onlineAvailable === 0 && storeAvailable > 0) ||
      (storeAvailable > 0 && buffer >= storeAvailable)
    );
  },

  async loadSkus() {
    this.tableBodyTarget.innerHTML = `
      <tr>
        <td colspan="11" class="table-empty">Loading...</td>
      </tr>
    `;

    try {
      const url = `/pos/skus/search?${new URLSearchParams(
        this.filtersForRequest(),
      ).toString()}`;

      const response = await fetch(url, {
        headers: this.jsonHeaders(),
      });

      const data = await this.parseJsonResponse(
        response,
        "loadSkus /pos/skus/search",
      );

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Failed to load skus");
      }

      this.currentSkus = data.skus || [];
      const visibleSkus = this.applyFrontendFilters(this.currentSkus);

      this.resultSummaryTarget.textContent =
        visibleSkus.length === this.currentSkus.length
          ? `Found ${data.count} SKU(s)`
          : `Showing ${visibleSkus.length} of ${this.currentSkus.length} SKU(s)`;

      if (visibleSkus.length === 0) {
        this.tableBodyTarget.innerHTML = `
          <tr>
            <td colspan="11" class="table-empty">ไม่พบสินค้า</td>
          </tr>
        `;
        return;
      }

      this.tableBodyTarget.innerHTML = visibleSkus
        .map((sku) => this.renderRowGroup(sku))
        .join("");
    } catch (error) {
      console.error("loadSkus error", error);
      this.resultSummaryTarget.textContent = "Load failed";
      this.tableBodyTarget.innerHTML = `
        <tr>
          <td colspan="11" class="table-empty">โหลดข้อมูลไม่สำเร็จ</td>
        </tr>
      `;
    }
  },

  renderCurrentTable() {
    const visibleSkus = this.applyFrontendFilters(this.currentSkus);

    this.tableBodyTarget.innerHTML = visibleSkus
      .map((sku) => this.renderRowGroup(sku))
      .join("");
  },

  renderRowGroup(sku) {
    return `
      ${this.renderRow(sku)}
      ${this.renderDetailRow(sku)}
    `;
  },

  renderRow(sku) {
    const channels = Array.isArray(sku.channel_shops) ? sku.channel_shops : [];
    const hasShop = (label) => channels.includes(label);

    return `
      <tr class="${this.rowClassNames(sku)}">
        <td>
          <div class="sku-code-link"
              data-action="click->product-management#openLedger"
              data-sku-id="${sku.id}">
            ${this.escapeHtml(sku.code || "-")}
          </div>

          ${this.renderTopBadges(sku)}

          <div class="sku-subtext">
            ${this.escapeHtml(sku.barcode || "-")}
          </div>

          <div class="sku-subtext sku-subtext--muted">
            OnHand ${sku.on_hand ?? 0} • Reserved ${sku.reserved ?? 0}
          </div>

          ${this.renderSkuBadges(sku)}
        </td>

        <td class="td-center">${this.renderChannelPill(hasShop("TikTok 1"))}</td>
        <td class="td-center">${this.renderChannelPill(hasShop("TikTok 2"))}</td>
        <td class="td-center">${this.renderChannelPill(hasShop("Lazada 1"))}</td>
        <td class="td-center">${this.renderChannelPill(hasShop("Lazada 2"))}</td>
        <td class="td-center">${this.renderChannelPill(hasShop("Shopee"))}</td>

        <td class="td-center">${this.escapeHtml(String(sku.store_available ?? 0))}</td>
        <td class="td-center">
          ${
            sku.frozen
              ? `<span class="text-muted">0 (Frozen)</span>`
              : this.escapeHtml(String(sku.online_available ?? 0))
          }
        </td>
        <td class="td-center">${this.escapeHtml(String(sku.buffer_quantity ?? 0))}</td>

        <td class="td-center">
          <span class="ui-pill ui-pill--status ${sku.active ? "is-active" : "is-inactive"}">
            ${sku.active ? "Active" : "Inactive"}
          </span>
        </td>

        <td class="td-center">
          <div class="row-actions row-actions--center row-actions--compact">
            <button
              type="button"
              class="ui-pill ui-pill--button"
              data-action="click->product-management#toggleDetails"
              data-sku-id="${sku.id}">
              ${this.expandedSkuIds.has(Number(sku.id)) ? "Hide" : "Details"}
            </button>

            <button
              type="button"
              class="ui-pill ui-pill--button"
              data-action="click->product-management#openAdjustModal"
              data-sku-id="${sku.id}">
              Adjust
            </button>
          </div>
        </td>
      </tr>
    `;
  },

  renderDetailRow(sku) {
    const isOpen = this.expandedSkuIds.has(Number(sku.id));

    return `
      <tr
        class="sku-detail-row ${isOpen ? "is-open" : ""}"
        data-detail-row-for="${sku.id}">
        <td colspan="11">
          <div class="sku-detail-panel ${isOpen ? "is-open" : ""}">
            <div class="sku-detail-grid">
              <div class="sku-detail-card ${this.cardClass(sku, "on_hand")}">
                <div class="sku-detail-card__label">On hand</div>
                <div class="sku-detail-card__value">${this.escapeHtml(String(sku.on_hand ?? 0))}</div>
              </div>

              <div class="sku-detail-card ${this.cardClass(sku, "reserved")}">
                <div class="sku-detail-card__label">Reserved</div>
                <div class="sku-detail-card__value">${this.escapeHtml(String(sku.reserved ?? 0))}</div>
              </div>

              <div class="sku-detail-card ${this.cardClass(sku, "store")}">
                <div class="sku-detail-card__label">Store available</div>
                <div class="sku-detail-card__value">${this.escapeHtml(String(sku.store_available ?? 0))}</div>
              </div>

              <div class="sku-detail-card ${this.cardClass(sku, "online")}">
                <div class="sku-detail-card__label">Online available</div>
                <div class="sku-detail-card__value">${this.escapeHtml(String(sku.online_available ?? 0))}</div>
              </div>

              <div class="sku-detail-card">
                <div class="sku-detail-card__label">Buffer</div>
                <div class="sku-detail-card__value">${this.escapeHtml(String(sku.buffer_quantity ?? 0))}</div>
              </div>

              <div class="sku-detail-card">
                <div class="sku-detail-card__label">Freeze</div>
                <div class="sku-detail-card__value ${sku.frozen ? "text-danger" : ""}">
                  ${
                    sku.frozen
                      ? `❄ ${this.escapeHtml(sku.freeze_reason || "frozen")}`
                      : "Normal"
                  }
                </div>
              </div>
            </div>

            <div class="sku-detail-meta">
              <div>
                <span class="sku-detail-meta__label">Brand/Model:</span>
                ${this.escapeHtml(`${sku.brand || "-"} / ${sku.model || "-"}`)}
              </div>

              <div>
                <span class="sku-detail-meta__label">Color/Size:</span>
                ${this.escapeHtml(`${sku.color || "-"} / ${sku.size || "-"}`)}
              </div>

              <div>
                <span class="sku-detail-meta__label">Channels:</span>
                ${this.escapeHtml((sku.channel_shops || []).join(", ") || "-")}
              </div>
            </div>

            ${this.renderRiskNotes(sku)}

            <div class="sku-detail-actions">
              <button
                type="button"
                class="ui-pill ui-pill--button ${sku.frozen ? "is-danger" : ""}"
                data-action="click->product-management#toggleFreeze"
                data-sku-id="${sku.id}">
                ${sku.frozen ? "Unfreeze" : "Freeze"}
              </button>

              <button
                type="button"
                class="ui-pill ui-pill--button"
                data-action="click->product-management#openLedger"
                data-sku-id="${sku.id}">
                Open Ledger
              </button>

              ${this.renderArchiveButton(sku)}
            </div>
          </div>
        </td>
      </tr>
    `;
  },

  renderRiskNotes(sku) {
    const notes = [];

    if (sku.frozen && sku.freeze_reason === "oversold") {
      notes.push("Oversold → marketplace stock may be forced to 0");
    }

    if (Number(sku.reserved || 0) > Number(sku.on_hand || 0)) {
      notes.push("Reserved is higher than on hand");
    }

    if (
      Number(sku.online_available || 0) === 0 &&
      Number(sku.store_available || 0) > 0
    ) {
      notes.push("Store has stock but online sellable is 0");
    }

    if (
      Number(sku.store_available || 0) > 0 &&
      Number(sku.buffer_quantity || 0) >= Number(sku.store_available || 0)
    ) {
      notes.push("Buffer is consuming all online sellable stock");
    }

    if (notes.length === 0) return "";

    return `
      <div class="sku-risk-notes">
        ${notes
          .map(
            (note) => `
              <div class="sku-risk-note">
                ${this.escapeHtml(note)}
              </div>
            `,
          )
          .join("")}
      </div>
    `;
  },

  renderTopBadges(sku) {
    if (!this.isRiskySku(sku)) return "";

    return `
      <div class="sku-top-badges">
        ${sku.frozen ? `<span class="badge badge--danger">Frozen</span>` : ""}
        ${
          sku.reserved > sku.on_hand
            ? `<span class="badge badge--danger">Oversell</span>`
            : ""
        }
        ${
          sku.online_available === 0 && sku.store_available > 0
            ? `<span class="badge badge--warning">No online</span>`
            : ""
        }
      </div>
    `;
  },

  renderSkuBadges(sku) {
    if (!sku.frozen) return "";

    const reason = (sku.freeze_reason || "").toLowerCase();

    if (reason === "oversold") {
      return `<div class="sku-badge sku-badge--oversold">Oversold</div>`;
    }

    if (reason === "not_enough_stock") {
      return `<div class="sku-badge sku-badge--low">Low stock</div>`;
    }

    if (reason === "manual") {
      return `<div class="sku-badge sku-badge--manual">Manual freeze</div>`;
    }

    return `<div class="sku-badge sku-badge--frozen">Frozen</div>`;
  },

  renderChannelPill(enabled) {
    if (enabled) {
      return `<span class="ui-pill ui-pill--channel is-yes">✓</span>`;
    }

    return `<span class="ui-pill ui-pill--channel is-no">✕</span>`;
  },

  renderArchiveButton(sku) {
    if (sku.active) {
      return `
        <button
          type="button"
          class="ui-pill ui-pill--button is-danger"
          data-action="click->product-management#archiveSku"
          data-sku-id="${sku.id}">
          Archive
        </button>
      `;
    }

    return `
      <button
        type="button"
        class="ui-pill ui-pill--button"
        data-action="click->product-management#unarchiveSku"
        data-sku-id="${sku.id}">
        Unarchive
      </button>
    `;
  },

  async archiveSku(event) {
    const skuId = Number(event.currentTarget.dataset.skuId);
    const sku = this.currentSkus.find((item) => Number(item.id) === skuId);

    if (!sku) return;

    if (
      !window.confirm(
        `Archive SKU นี้?\n\n${sku.code}\n\nหลัง archive จะไม่โชว์ในหน้า default และ dropdown`,
      )
    ) {
      return;
    }

    const button = event.currentTarget;
    const originalText = button.textContent;

    button.disabled = true;
    button.textContent = "Archiving...";

    try {
      const response = await fetch(`/ops/products/${skuId}/archive`, {
        method: "PATCH",
        headers: this.jsonHeaders({
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken(),
        }),
      });

      const data = await this.parseJsonResponse(
        response,
        `/ops/products/${skuId}/archive`,
      );

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Archive failed");
      }

      await this.refreshAll();
    } catch (error) {
      console.error("archiveSku error", error);
      window.alert(error.message);
    } finally {
      button.disabled = false;
      button.textContent = originalText;
    }
  },

  async unarchiveSku(event) {
    const skuId = Number(event.currentTarget.dataset.skuId);
    const button = event.currentTarget;
    const originalText = button.textContent;

    button.disabled = true;
    button.textContent = "Unarchiving...";

    try {
      const response = await fetch(`/ops/products/${skuId}/unarchive`, {
        method: "PATCH",
        headers: this.jsonHeaders({
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken(),
        }),
      });

      const data = await this.parseJsonResponse(
        response,
        `/ops/products/${skuId}/unarchive`,
      );

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Unarchive failed");
      }

      await this.refreshAll();
    } catch (error) {
      console.error("unarchiveSku error", error);
      window.alert(error.message);
    } finally {
      button.disabled = false;
      button.textContent = originalText;
    }
  },

  rowClassNames(sku) {
    const classes = [];

    if (sku.frozen) classes.push("sku-row--frozen");
    if (this.isRiskySku(sku)) classes.push("sku-row--risky");

    return classes.join(" ");
  },

  cardClass(sku, field) {
    if (field === "online" && Number(sku.online_available || 0) === 0) {
      return "sku-detail-card--danger";
    }

    if (
      field === "reserved" &&
      Number(sku.reserved || 0) > Number(sku.on_hand || 0)
    ) {
      return "sku-detail-card--danger";
    }

    if (
      field === "store" &&
      Number(sku.store_available || 0) > 0 &&
      Number(sku.online_available || 0) === 0
    ) {
      return "sku-detail-card--warning";
    }

    if (field === "online") {
      return "sku-detail-card--primary";
    }

    return "";
  },

  toggleDetails(event) {
    const skuId = Number(event.currentTarget.dataset.skuId);

    if (this.expandedSkuIds.has(skuId)) {
      this.expandedSkuIds.delete(skuId);
    } else {
      this.expandedSkuIds.add(skuId);
    }

    this.renderCurrentTable();
  },

  async toggleFreeze(event) {
    const skuId = Number(event.currentTarget.dataset.skuId);
    const sku = this.currentSkus.find((item) => item.id === skuId);
    if (!sku) return;

    const action = sku.frozen ? "unfreeze" : "freeze";
    const originalText = event.currentTarget.textContent;

    event.currentTarget.disabled = true;
    event.currentTarget.textContent =
      action === "freeze" ? "Freezing..." : "Unfreezing...";

    try {
      const response = await fetch(`/pos/skus/${skuId}/${action}`, {
        method: "POST",
        headers: this.jsonHeaders({
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken(),
        }),
        body: JSON.stringify({
          idempotency_key: `ui:${action}:${Date.now()}:${Math.random()
            .toString(36)
            .slice(2, 10)}`,
        }),
      });

      const data = await this.parseJsonResponse(
        response,
        `toggleFreeze /pos/skus/${skuId}/${action}`,
      );

      if (!response.ok || !data.ok) {
        throw new Error(data.error || `${action} failed`);
      }

      await this.loadSkus();

      if (
        this.currentLedgerSkuId &&
        Number(this.currentLedgerSkuId) === Number(skuId)
      ) {
        await this.loadLedger(skuId);
      }
    } catch (error) {
      console.error("toggleFreeze error", error);
      window.alert(error.message);
    } finally {
      event.currentTarget.disabled = false;
      event.currentTarget.textContent = originalText;
    }
  },
};
