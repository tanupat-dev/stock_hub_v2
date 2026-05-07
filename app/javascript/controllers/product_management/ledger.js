export const productManagementLedgerMethods = {
  async loadLedger(skuId) {
    this.currentLedgerSkuId = skuId;
    this.ledgerDrawerTarget.classList.add("is-open");
    this.ledgerListTarget.innerHTML = `<div class="ledger-loading">Loading...</div>`;
    this.ledgerEmptyTarget.style.display = "none";

    const sku = this.currentSkus?.find(
      (item) => Number(item.id) === Number(skuId),
    );

    if (sku) {
      this.ledgerSkuSummaryTarget.textContent =
        `${sku.code} • ${sku.brand || "-"} ${sku.model || ""}`.trim();
    }

    try {
      const response = await fetch(`/pos/skus/${skuId}/ledger?limit=100`, {
        headers: this.jsonHeaders(),
      });

      const data = await this.parseJsonResponse(
        response,
        `/pos/skus/${skuId}/ledger`,
      );

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Failed to load ledger");
      }

      const ledger = data.ledger?.entries || [];
      const skuData = data.sku || sku || {};

      this.ledgerSkuSummaryTarget.innerHTML =
        this.renderLedgerSkuSummary(skuData);

      if (ledger.length === 0) {
        this.ledgerListTarget.innerHTML = "";
        this.ledgerEmptyTarget.style.display = "block";
        this.ledgerEmptyTarget.textContent = "ยังไม่มี ledger entries";
        return;
      }

      this.ledgerEmptyTarget.style.display = "none";
      this.ledgerListTarget.innerHTML = this.renderLedgerEntries(ledger);
    } catch (error) {
      console.error("loadLedger error", error);
      this.ledgerListTarget.innerHTML =
        `<div class="ledger-error">โหลด ledger ไม่สำเร็จ</div>`;
    }
  },

  closeLedger() {
    this.ledgerDrawerTarget.classList.remove("is-open");
    this.currentLedgerSkuId = null;
  },

  renderLedgerSkuSummary(sku) {
    const code = sku.code || "-";
    const store = sku.store_available ?? 0;
    const online = sku.online_available ?? 0;
    const onHand = sku.on_hand ?? sku.balance?.on_hand;
    const reserved = sku.reserved ?? sku.balance?.reserved;

    const stockParts = [
      `Store ${store}`,
      `Online ${online}`,
    ];

    if (onHand != null) stockParts.unshift(`On hand ${onHand}`);
    if (reserved != null) stockParts.splice(1, 0, `Reserved ${reserved}`);

    return `
      <span class="ledger-summary-line">
        <strong>${this.escapeHtml(code)}</strong>
        <span>${this.escapeHtml(stockParts.join(" • "))}</span>
      </span>
    `;
  },

  renderLedgerEntries(entries) {
    const grouped = this.groupLedgerEntriesByDay(entries);

    return Object.entries(grouped)
      .map(([day, rows]) => {
        return `
          <section class="ledger-day-group">
            <div class="ledger-day-group__title">${this.escapeHtml(day)}</div>
            ${rows.map((entry) => this.renderLedgerEntry(entry)).join("")}
          </section>
        `;
      })
      .join("");
  },

  groupLedgerEntriesByDay(entries) {
    return entries.reduce((memo, entry) => {
      const key =
        entry.day_group ||
        this.ledgerDayFromValue(entry.occurred_at_th || entry.occurred_at);

      if (!memo[key]) memo[key] = [];
      memo[key].push(entry);

      return memo;
    }, {});
  },

  ledgerDayFromValue(value) {
    if (!value) return "-";

    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) return "-";

    return parsed.toLocaleDateString("th-TH", {
      year: "numeric",
      month: "short",
      day: "numeric",
    });
  },

  renderLedgerEntry(entry) {
    const title =
      entry.action_label ||
      (entry.source_type === "inventory_action"
        ? entry.action_type || "inventory_action"
        : entry.reason || "stock_movement");

    const actionClass = this.ledgerActionClass(entry);
    const deltaLabel =
      entry.delta_label || this.fallbackLedgerDeltaLabel(entry);

    const quantity = entry.quantity == null ? "-" : entry.quantity;
    const meta = this.escapeHtml(JSON.stringify(entry.meta || {}, null, 2));

    return `
      <article class="ledger-entry ledger-entry--${this.escapeHtml(actionClass)}">
        <div class="ledger-entry__top">
          <div>
            <div class="ledger-entry__title-row">
              <span class="ledger-action-badge ledger-action-badge--${this.escapeHtml(actionClass)}">
                ${this.escapeHtml(title)}
              </span>
              <span class="ledger-entry__source">
                ${this.escapeHtml(entry.source_type || "-")}
              </span>
            </div>

            <div class="ledger-entry__sub">
              ${this.escapeHtml(entry.occurred_at_th || entry.occurred_at || "-")}
            </div>
          </div>

          <div class="ledger-entry__delta">
            ${this.escapeHtml(deltaLabel)}
          </div>
        </div>

        <div class="ledger-entry__meta-row">
          <span>Qty: ${this.escapeHtml(String(quantity))}</span>
          <span>ID: ${this.escapeHtml(String(entry.id || "-"))}</span>
          ${this.renderLedgerDeltaChip("On hand", entry.delta_on_hand)}
          ${this.renderLedgerDeltaChip("Reserved", entry.delta_reserved)}
          ${this.renderLedgerMetaBadges(entry)}
        </div>

        ${this.renderLedgerOrderBlock(entry)}
        ${this.renderLedgerIdempotency(entry)}

        <details class="ledger-entry__details">
          <summary>Meta</summary>
          <pre>${meta}</pre>
        </details>
      </article>
    `;
  },

  renderLedgerDeltaChip(label, value) {
    if (value == null || Number(value) === 0) return "";

    return `<span>${this.escapeHtml(label)}: ${this.escapeHtml(this.signedLedgerNumber(value))}</span>`;
  },

  renderLedgerMetaBadges(entry) {
    const meta = entry.extracted_meta || entry.meta || {};
    const badges = [];

    if (meta.shortfall != null) {
      badges.push(
        `<span class="ledger-badge ledger-badge--warn">Shortfall ${this.escapeHtml(String(meta.shortfall))}</span>`,
      );
    }

    if (meta.adjust_mode) {
      badges.push(
        `<span class="ledger-badge">${this.escapeHtml(meta.adjust_mode)}</span>`,
      );
    }

    if (meta.source) {
      badges.push(
        `<span class="ledger-badge">${this.escapeHtml(meta.source)}</span>`,
      );
    }

    if (meta.scan_match_type) {
      badges.push(
        `<span class="ledger-badge">${this.escapeHtml(meta.scan_match_type)}</span>`,
      );
    }

    return badges.join("");
  },

  renderLedgerOrderBlock(entry) {
    const order = entry.order;
    const line = entry.order_line;

    if (!order && !line) return "";

    return `
      <div class="ledger-entry__order">
        ${
          order
            ? `
              <div>
                <span class="ledger-entry__label">Order</span>
                <strong>${this.escapeHtml(order.external_order_id || "-")}</strong>
              </div>
              <div>
                <span class="ledger-entry__label">Channel</span>
                ${this.escapeHtml(order.channel || "-")}
                ${order.shop_label ? `• ${this.escapeHtml(order.shop_label)}` : ""}
              </div>
              <div>
                <span class="ledger-entry__label">Status</span>
                ${this.escapeHtml(order.status || "-")}
              </div>
            `
            : ""
        }

        ${
          line
            ? `
              <div>
                <span class="ledger-entry__label">Line</span>
                ${this.escapeHtml(line.external_line_id || line.id || "-")}
                ${line.external_sku ? `• ${this.escapeHtml(line.external_sku)}` : ""}
              </div>
            `
            : ""
        }
      </div>
    `;
  },

  renderLedgerIdempotency(entry) {
    if (!entry.idempotency_key) return "";

    const shortKey =
      entry.idempotency_key_short ||
      this.shortenLedgerKey(entry.idempotency_key);

    return `
      <div
        class="ledger-entry__idempotency"
        title="${this.escapeAttribute(entry.idempotency_key)}">
        <span>Key</span>
        <code>${this.escapeHtml(shortKey)}</code>
      </div>
    `;
  },

  ledgerActionClass(entry) {
    const raw = String(
      entry.action_type || entry.reason || entry.source_type || "",
    )
      .toLowerCase()
      .replaceAll("_", "-");

    if (raw.includes("reserve")) return "reserve";
    if (raw.includes("commit")) return "commit";
    if (raw.includes("release")) return "release";
    if (raw.includes("return-scan")) return "return-scan";
    if (raw.includes("stock-in")) return "stock-in";
    if (raw.includes("stock-adjust")) return "stock-adjust";
    if (raw.includes("movement")) return "movement";

    return "neutral";
  },

  fallbackLedgerDeltaLabel(entry) {
    if (entry.delta_on_hand == null) return "No stock delta";

    return `On hand ${this.signedLedgerNumber(entry.delta_on_hand)}`;
  },

  signedLedgerNumber(value) {
    const n = Number(value || 0);
    return n > 0 ? `+${n}` : String(n);
  },

  shortenLedgerKey(value) {
    const raw = String(value || "");
    if (raw.length <= 34) return raw;

    return `${raw.slice(0, 18)}...${raw.slice(-12)}`;
  },

  escapeAttribute(value) {
    return this.escapeHtml(value);
  },
};
