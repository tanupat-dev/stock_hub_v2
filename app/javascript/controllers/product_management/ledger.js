export const productManagementLedgerMethods = {
  async loadLedger(skuId) {
    this.currentLedgerSkuId = skuId;
    this.ledgerDrawerTarget.classList.add("is-open");
    this.ledgerListTarget.innerHTML = `<div class="ledger-loading">Loading...</div>`;
    this.ledgerEmptyTarget.style.display = "none";

    const fallbackSku = this.currentSkus?.find(
      (item) => Number(item.id) === Number(skuId),
    );

    if (fallbackSku) {
      this.ledgerSkuSummaryTarget.innerHTML =
        this.renderLedgerSkuSummary(fallbackSku);
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

      const sku = data.sku || fallbackSku || {};
      const entries = data.ledger?.entries || [];

      this.ledgerSkuSummaryTarget.innerHTML = this.renderLedgerSkuSummary(sku);

      if (entries.length === 0) {
        this.ledgerListTarget.innerHTML = "";
        this.ledgerEmptyTarget.style.display = "block";
        this.ledgerEmptyTarget.textContent = "ยังไม่มี ledger entries";
        return;
      }

      this.ledgerEmptyTarget.style.display = "none";
      this.ledgerListTarget.innerHTML = this.renderLedgerEntries(entries);
    } catch (error) {
      console.error("loadLedger error", error);
      this.ledgerListTarget.innerHTML = `<div class="ledger-error">โหลด ledger ไม่สำเร็จ</div>`;
    }
  },

  closeLedger() {
    this.ledgerDrawerTarget.classList.remove("is-open");
    this.currentLedgerSkuId = null;
  },

  renderLedgerSkuSummary(sku) {
    const code = sku.code || "-";
    const barcode = sku.barcode || "-";
    const onHand = sku.on_hand ?? sku.balance?.on_hand ?? 0;
    const reserved = sku.reserved ?? sku.balance?.reserved ?? 0;
    const store = sku.store_available ?? 0;
    const online = sku.online_available ?? 0;

    const groupMembers = Array.isArray(sku.group_members)
      ? sku.group_members
      : [];

    const groupHtml =
      groupMembers.length > 1
        ? `
          <div class="ledger-summary-clean__group">
            <span>Shared stock</span>
            ${groupMembers
              .map(
                (member) => `
                  <span class="ledger-clean-pill ${member.active ? "" : "is-muted"}">
                    ${this.escapeHtml(member.code || "-")}
                  </span>
                `,
              )
              .join("")}
          </div>
        `
        : "";

    const frozenHtml = sku.frozen
      ? `
        <div class="ledger-summary-clean__alert">
          Frozen: ${this.escapeHtml(sku.freeze_reason || "frozen")}
        </div>
      `
      : "";

    return `
      <div class="ledger-summary-clean">
        <div class="ledger-summary-clean__title">
          <strong>${this.escapeHtml(code)}</strong>
          <span>${this.escapeHtml(barcode)}</span>
        </div>

        <div class="ledger-summary-clean__stats">
          <span>On hand <strong>${this.escapeHtml(String(onHand))}</strong></span>
          <span>Reserved <strong>${this.escapeHtml(String(reserved))}</strong></span>
          <span>Store <strong>${this.escapeHtml(String(store))}</strong></span>
          <span>Online <strong>${this.escapeHtml(String(online))}</strong></span>
        </div>

        ${frozenHtml}
        ${groupHtml}
      </div>
    `;
  },

  renderLedgerEntries(entries) {
    const grouped = this.groupLedgerEntriesByDay(entries);

    return Object.entries(grouped)
      .map(([day, rows]) => {
        return `
          <section class="ledger-day-group ledger-day-group--clean">
            <div class="ledger-day-group__title">${this.escapeHtml(day)}</div>
            <div class="ledger-timeline-clean">
              ${rows.map((entry) => this.renderLedgerEntry(entry)).join("")}
            </div>
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

    return parsed.toLocaleDateString("en-GB", {
      day: "2-digit",
      month: "short",
      year: "numeric",
    });
  },

  renderLedgerEntry(entry) {
    const title = this.ledgerEntryTitle(entry);
    const actionClass = this.ledgerActionClass(entry);
    const time = this.cleanLedgerTime(
      entry.occurred_at_th || entry.occurred_at,
    );
    const deltaLabel = this.ledgerDeltaLabel(entry);
    const facts = this.renderLedgerFacts(entry);
    const orderBlock = this.renderLedgerOrderBlock(entry);
    const details = this.renderLedgerDetails(entry);

    return `
      <article class="ledger-entry-clean ledger-entry-clean--${this.escapeHtml(actionClass)}">
        <div class="ledger-entry-clean__rail">
          <span class="ledger-entry-clean__dot ledger-entry-clean__dot--${this.escapeHtml(actionClass)}"></span>
        </div>

        <div class="ledger-entry-clean__card">
          <div class="ledger-entry-clean__top">
            <div class="ledger-entry-clean__main">
              <div class="ledger-entry-clean__title">
                ${this.escapeHtml(title)}
              </div>
              <div class="ledger-entry-clean__time">
                ${this.escapeHtml(time)}
              </div>
            </div>

            ${
              deltaLabel
                ? `
                  <div class="ledger-entry-clean__delta ledger-entry-clean__delta--${this.escapeHtml(actionClass)}">
                    ${this.escapeHtml(deltaLabel)}
                  </div>
                `
                : ""
            }
          </div>

          ${facts ? `<div class="ledger-entry-clean__facts">${facts}</div>` : ""}

          ${orderBlock}
          ${details}
        </div>
      </article>
    `;
  },

  ledgerEntryTitle(entry) {
    const meta = this.ledgerMergedMeta(entry);

    if (entry.source_type === "stock_movement") {
      const delta = Number(entry.delta_on_hand || 0);
      if (delta > 0) return "Stock in";
      if (delta < 0) return "Stock out";
      return "Stock movement";
    }

    if (entry.action_type === "stock_adjust") {
      if (meta.set_to != null && meta.set_to !== "") {
        return `Set stock to ${meta.set_to}`;
      }

      if (meta.delta != null && meta.delta !== "") {
        return `Adjust stock ${this.signedLedgerNumber(meta.delta)}`;
      }

      return "Stock adjust";
    }

    if (entry.action_label) return entry.action_label;

    return this.humanizeLedgerText(entry.action_type || "Ledger event");
  },

  renderLedgerFacts(entry) {
    const facts = [];

    if (this.shouldShowQuantity(entry)) {
      facts.push({
        label: "Qty",
        value: entry.quantity,
        tone: "strong",
      });
    }

    const source = this.ledgerPrimarySource(entry);
    if (source) {
      facts.push({
        label: "Source",
        value: source,
        tone: "muted",
      });
    }

    const meta = this.ledgerMergedMeta(entry);
    const shortfall = Number(meta.shortfall || 0);
    if (shortfall > 0) {
      facts.push({
        label: "Shortfall",
        value: shortfall,
        tone: "danger",
      });
    }

    return facts
      .map(
        (fact) => `
          <span class="ledger-clean-fact ledger-clean-fact--${this.escapeHtml(fact.tone)}">
            <span>${this.escapeHtml(fact.label)}</span>
            <strong>${this.escapeHtml(String(fact.value))}</strong>
          </span>
        `,
      )
      .join("");
  },

  shouldShowQuantity(entry) {
    if (entry.quantity == null) return false;

    if (entry.action_type === "reserve") return true;
    if (entry.action_type === "release") return true;
    if (entry.action_type === "commit") return true;
    if (entry.action_type === "return_scan") return true;
    if (entry.action_type === "stock_in") return true;

    const meta = this.ledgerMergedMeta(entry);
    if (entry.action_type === "stock_adjust" && meta.set_to != null) {
      return false;
    }

    return Number(entry.quantity) !== 0;
  },

  ledgerPrimarySource(entry) {
    const meta = this.ledgerMergedMeta(entry);

    if (entry.order) return null;

    const source = meta.source || entry.reason;
    if (!source) return null;

    const normalized = String(source);

    if (normalized === "stock_adjust") return "Manual adjust";
    if (normalized === "sku_import") return "SKU import";
    if (normalized === "orders_apply_policy") return "Order policy";

    return this.humanizeLedgerText(normalized);
  },

  renderLedgerOrderBlock(entry) {
    const order = entry.order;
    const line = entry.order_line;

    if (!order && !line) return "";

    const channelLabel =
      order?.shop_label || this.humanizeLedgerText(order?.channel || "-");

    const lineSku = line?.external_sku || line?.sku_code || "-";

    return `
      <div class="ledger-clean-order">
        ${
          order
            ? `
              <div class="ledger-clean-order__row">
                <span>Order</span>
                <strong>${this.escapeHtml(order.external_order_id || "-")}</strong>
              </div>

              <div class="ledger-clean-order__row">
                <span>Channel</span>
                <strong>${this.escapeHtml(channelLabel)}</strong>
              </div>

              <div class="ledger-clean-order__row">
                <span>Status</span>
                <strong>${this.escapeHtml(order.status || "-")}</strong>
              </div>
            `
            : ""
        }

        ${
          line
            ? `
              <div class="ledger-clean-order__row">
                <span>SKU</span>
                <strong>${this.escapeHtml(lineSku)}</strong>
              </div>
            `
            : ""
        }
      </div>
    `;
  },

  renderLedgerDetails(entry) {
    const meta = this.escapeHtml(JSON.stringify(entry.meta || {}, null, 2));
    const key = entry.idempotency_key || "";

    return `
      <details class="ledger-clean-details">
        <summary>Details</summary>

        ${
          key
            ? `
              <div class="ledger-clean-key">
                <span>Key</span>
                <code title="${this.escapeAttribute(key)}">
                  ${this.escapeHtml(entry.idempotency_key_short || this.shortenLedgerKey(key))}
                </code>
              </div>
            `
            : ""
        }

        <pre>${meta}</pre>
      </details>
    `;
  },

  ledgerDeltaLabel(entry) {
    const meta = this.ledgerMergedMeta(entry);

    const onHand = Number(entry.delta_on_hand || 0);
    const reserved = Number(entry.delta_reserved || 0);

    if (onHand !== 0 && reserved !== 0) {
      return `On hand ${this.signedLedgerNumber(onHand)} · Reserved ${this.signedLedgerNumber(reserved)}`;
    }

    if (onHand !== 0) {
      return `On hand ${this.signedLedgerNumber(onHand)}`;
    }

    if (reserved !== 0) {
      return `Reserved ${this.signedLedgerNumber(reserved)}`;
    }

    if (
      entry.action_type === "stock_adjust" &&
      meta.set_to != null &&
      meta.set_to !== ""
    ) {
      return `Set to ${meta.set_to}`;
    }

    if (
      entry.action_type === "stock_adjust" &&
      meta.delta != null &&
      meta.delta !== ""
    ) {
      return `Delta ${this.signedLedgerNumber(meta.delta)}`;
    }

    if (entry.delta_label && entry.delta_label !== "No stock delta") {
      return entry.delta_label.replace(" / ", " · ");
    }

    return "";
  },

  ledgerMergedMeta(entry) {
    return {
      ...(entry.meta || {}),
      ...(entry.extracted_meta || {}),
    };
  },

  ledgerActionClass(entry) {
    if (entry.source_type === "stock_movement") return "movement";

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

    return "neutral";
  },

  cleanLedgerTime(value) {
    if (!value) return "-";

    const raw = String(value)
      .replace(/\s+ICT$/i, "")
      .trim();

    const parsed = new Date(raw);
    if (!Number.isNaN(parsed.getTime())) {
      return parsed.toLocaleString("en-GB", {
        day: "2-digit",
        month: "short",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
      });
    }

    return raw;
  },

  humanizeLedgerText(value) {
    return String(value || "")
      .replaceAll("_", " ")
      .replaceAll("-", " ")
      .replace(/\b\w/g, (char) => char.toUpperCase());
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
