import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "qInput",
    "brandSelect",
    "modelSelect",
    "colorSelect",
    "sizeSelect",
    "limitSelect",
    "statusSelect",
    "riskFilterSelect",
    "tableBody",
    "resultSummary",
    "ledgerDrawer",
    "ledgerSkuSummary",
    "ledgerList",
    "ledgerEmpty",
    "modalBackdrop",
    "adjustModal",
    "adjustSkuSummary",
    "adjustSkuId",
    "adjustMode",
    "quantityField",
    "deltaField",
    "setToField",
    "bufferField",
    "quantityInput",
    "deltaInput",
    "setToInput",
    "bufferInput",
    "reasonInput",
    "noteInput",
    "adjustMessage",
    "adjustWarning",
    "importModalBackdrop",
    "importModal",
    "importFileInput",
    "importFilePicker",
    "importSelectedFileTitle",
    "importSelectedFileMeta",
    "importMessage",
    "importResult",
    "importSubmitButton",
    "importDryRunCheckbox",
    "importStockModeSelect",
  ];

  connect() {
    this.searchDebounce = null;
    this.currentSkus = [];
    this.currentLedgerSkuId = null;
    this.expandedSkuIds = new Set();

    this.loadFacets();
    this.loadSkus();
    this.onAdjustModeChange();

    this.adjustModeTarget.addEventListener("change", () =>
      this.updateAdjustWarning(),
    );
    this.deltaInputTarget.addEventListener("input", () =>
      this.updateAdjustWarning(),
    );
    this.setToInputTarget.addEventListener("input", () =>
      this.updateAdjustWarning(),
    );
  }

  refreshAll() {
    this.loadFacets();
    this.loadSkus();
    if (this.currentLedgerSkuId) {
      this.loadLedger(this.currentLedgerSkuId);
    }
  }

  onFilterInput() {
    clearTimeout(this.searchDebounce);
    this.searchDebounce = setTimeout(() => {
      this.loadFacets();
      this.loadSkus();
    }, 300);
  }

  onFilterChange() {
    this.loadFacets();
    this.loadSkus();
  }

  resetFilters() {
    this.qInputTarget.value = "";
    this.brandSelectTarget.value = "";
    this.modelSelectTarget.value = "";
    this.colorSelectTarget.value = "";
    this.sizeSelectTarget.value = "";
    this.limitSelectTarget.value = "50";
    this.statusSelectTarget.value = "active";

    if (this.hasRiskFilterSelectTarget) {
      this.riskFilterSelectTarget.value = "all";
    }

    this.loadFacets();
    this.loadSkus();
  }

  openImportModal() {
    this.importFileInputTarget.value = "";
    this.importFilePickerTarget.classList.remove("is-selected");
    this.importSelectedFileTitleTarget.textContent = "Choose CSV file";
    this.importSelectedFileMetaTarget.textContent = "CSV only";

    if (this.hasImportDryRunCheckboxTarget) {
      this.importDryRunCheckboxTarget.checked = false;
    }

    this.hideImportMessage();
    this.hideImportResult();

    this.importModalBackdropTarget.classList.remove("hidden");
    this.importModalTarget.classList.remove("hidden");
  }

  closeImportModal(event) {
    if (event && event.target === this.importModalTarget) return;

    this.importModalBackdropTarget.classList.add("hidden");
    this.importModalTarget.classList.add("hidden");
  }

  onImportFileChange() {
    const file = this.importFileInputTarget.files[0];

    if (!file) {
      this.importFilePickerTarget.classList.remove("is-selected");
      this.importSelectedFileTitleTarget.textContent = "Choose CSV file";
      this.importSelectedFileMetaTarget.textContent = "CSV only";
      return;
    }

    this.importFilePickerTarget.classList.add("is-selected");
    this.importSelectedFileTitleTarget.textContent = file.name;
    this.importSelectedFileMetaTarget.textContent = this.humanFileSize(
      file.size,
    );
  }

  async submitImport() {
    const file = this.importFileInputTarget.files[0];

    if (!file) {
      this.showImportMessage("error", "Please choose a CSV file");
      return;
    }

    const dryRun = this.hasImportDryRunCheckboxTarget
      ? this.importDryRunCheckboxTarget.checked
      : false;

    let stockMode = "skip";

    if (this.hasImportStockModeSelectTarget) {
      const selected = this.importStockModeSelectTargets.find(
        (el) => el.checked,
      );
      if (selected) stockMode = selected.value;
    }

    const formData = new FormData();
    formData.append("file", file);

    const url = new URL("/ops/sku_imports", window.location.origin);
    if (dryRun) url.searchParams.set("dry_run", "true");
    if (stockMode) url.searchParams.set("stock_mode", stockMode);

    this.importSubmitButtonTarget.disabled = true;
    this.importSubmitButtonTarget.textContent = dryRun
      ? "Previewing..."
      : "Uploading...";
    this.hideImportMessage();
    this.hideImportResult();

    try {
      const response = await fetch(url.toString(), {
        method: "POST",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": this.csrfToken(),
        },
        body: formData,
      });

      const data = await this.parseJsonResponse(
        response,
        "submitImport /ops/sku_imports",
      );

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Upload failed");
      }

      this.showImportMessage(
        "success",
        data.result?.dry_run ? "Preview completed" : "Import completed",
      );

      this.renderImportResult(data.result);

      if (!data.result?.dry_run) {
        await this.loadSkus();
        await this.loadFacets();
      }
    } catch (error) {
      console.error("submitImport error", error);
      this.showImportMessage("error", error.message);
    } finally {
      this.importSubmitButtonTarget.disabled = false;
      this.importSubmitButtonTarget.textContent = "Upload CSV";
    }
  }

  async loadFacets() {
    try {
      const url = `/pos/skus/facets?${new URLSearchParams(this.filtersForRequest()).toString()}`;
      const response = await fetch(url, {
        headers: this.jsonHeaders(),
      });
      const data = await this.parseJsonResponse(
        response,
        "loadFacets /pos/skus/facets",
      );

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Failed to load facets");
      }

      this.populateSelect(
        this.brandSelectTarget,
        data.facets.brands,
        this.brandSelectTarget.value,
        "All brands",
      );
      this.populateSelect(
        this.modelSelectTarget,
        data.facets.models,
        this.modelSelectTarget.value,
        "All models",
      );
      this.populateSelect(
        this.colorSelectTarget,
        data.facets.colors,
        this.colorSelectTarget.value,
        "All colors",
      );
      this.populateSelect(
        this.sizeSelectTarget,
        data.facets.sizes,
        this.sizeSelectTarget.value,
        "All sizes",
      );
    } catch (error) {
      console.error("loadFacets error", error);
    }
  }

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
  }

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
  }

  async loadSkus() {
    this.tableBodyTarget.innerHTML = `
      <tr>
        <td colspan="11" class="table-empty">Loading...</td>
      </tr>
    `;

    try {
      const url = `/pos/skus/search?${new URLSearchParams(this.filtersForRequest()).toString()}`;
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
  }

  renderCurrentTable() {
    const visibleSkus = this.applyFrontendFilters(this.currentSkus);
    this.tableBodyTarget.innerHTML = visibleSkus
      .map((sku) => this.renderRowGroup(sku))
      .join("");
  }

  renderRowGroup(sku) {
    return `
      ${this.renderRow(sku)}
      ${this.renderDetailRow(sku)}
    `;
  }

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
  }

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
            </div>
          </div>
        </td>
      </tr>
    `;
  }

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
  }

  renderTopBadges(sku) {
    if (!this.isRiskySku(sku)) return "";

    return `
      <div class="sku-top-badges">
        ${sku.frozen ? `<span class="badge badge--danger">Frozen</span>` : ""}
        ${sku.reserved > sku.on_hand ? `<span class="badge badge--danger">Oversell</span>` : ""}
        ${sku.online_available === 0 && sku.store_available > 0 ? `<span class="badge badge--warning">No online</span>` : ""}
      </div>
    `;
  }

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
  }

  renderChannelPill(enabled) {
    if (enabled) {
      return `<span class="ui-pill ui-pill--channel is-yes">✓</span>`;
    }

    return `<span class="ui-pill ui-pill--channel is-no">✕</span>`;
  }

  rowClassNames(sku) {
    const classes = [];

    if (sku.frozen) classes.push("sku-row--frozen");
    if (this.isRiskySku(sku)) classes.push("sku-row--risky");

    return classes.join(" ");
  }

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
  }

  toggleDetails(event) {
    const skuId = Number(event.currentTarget.dataset.skuId);

    if (this.expandedSkuIds.has(skuId)) {
      this.expandedSkuIds.delete(skuId);
    } else {
      this.expandedSkuIds.add(skuId);
    }

    this.renderCurrentTable();
  }

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
          idempotency_key: `ui:${action}:${Date.now()}:${Math.random().toString(36).slice(2, 10)}`,
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
  }

  renderImportResult(result) {
    const items = [
      ["Rows", result.total_rows ?? 0],
      ["Upsert", result.upsert_rows ?? 0],
      ["Duplicate", result.duplicate_rows_in_file ?? 0],
      ["Invalid", result.invalid_format_rows ?? 0],
    ];

    const stockItems = [];
    const hasStock =
      result.stock_updated != null || result.stock_failed != null;

    if (result.stock_updated != null) {
      stockItems.push(["Stock Updated", result.stock_updated]);
    }

    if (result.stock_failed != null) {
      stockItems.push(["Stock Failed", result.stock_failed]);
    }

    const dryRunBadge = result.dry_run
      ? `
        <div style="margin-bottom: 10px; font-size: 12px; font-weight: 700; color: #2563eb;">
          PREVIEW ONLY • no data was saved
        </div>
      `
      : "";

    const baseHtml = `
      <div class="import-result-mini">
        ${items
          .map(
            ([label, value]) => `
          <div class="import-result-mini__item">
            <div class="import-result-mini__label">${this.escapeHtml(label)}</div>
            <div class="import-result-mini__value">${this.escapeHtml(String(value))}</div>
          </div>
        `,
          )
          .join("")}
      </div>
    `;

    const stockHtml = hasStock
      ? `
      <div class="import-result-mini" style="margin-top: 12px;">
        ${stockItems
          .map(
            ([label, value]) => `
          <div class="import-result-mini__item">
            <div class="import-result-mini__label">${this.escapeHtml(label)}</div>
            <div class="import-result-mini__value ${
              label.includes("Failed") ? "text-danger" : ""
            }">
              ${this.escapeHtml(String(value))}
            </div>
          </div>
        `,
          )
          .join("")}
      </div>
    `
      : "";

    const errorListHtml =
      result.stock_failed_samples?.length > 0
        ? `
      <div style="margin-top: 8px;">
        ${result.stock_failed_samples
          .map(
            (item) => `
          <div style="font-size: 12px; color: #dc2626;">
            ${this.escapeHtml(item.sku)} — ${this.escapeHtml(item.error)}
          </div>
        `,
          )
          .join("")}
      </div>
    `
        : "";

    this.importResultTarget.innerHTML =
      dryRunBadge + baseHtml + stockHtml + errorListHtml;

    this.importResultTarget.classList.remove("hidden");
  }

  showImportMessage(type, text) {
    this.importMessageTarget.textContent = text;
    this.importMessageTarget.classList.remove(
      "hidden",
      "is-error",
      "is-success",
    );
    this.importMessageTarget.classList.add(
      type === "error" ? "is-error" : "is-success",
    );
  }

  hideImportMessage() {
    this.importMessageTarget.textContent = "";
    this.importMessageTarget.classList.add("hidden");
    this.importMessageTarget.classList.remove("is-error", "is-success");
  }

  hideImportResult() {
    this.importResultTarget.innerHTML = "";
    this.importResultTarget.classList.add("hidden");
  }

  closeAdjustModal(event) {
    if (event && event.target === this.adjustModalTarget) return;
    this.modalBackdropTarget.classList.add("hidden");
    this.adjustModalTarget.classList.add("hidden");
  }

  onAdjustModeChange() {
    const mode = this.adjustModeTarget.value;

    this.quantityFieldTarget.classList.toggle("hidden", mode !== "stock_in");
    this.deltaFieldTarget.classList.toggle("hidden", mode !== "adjust_delta");
    this.setToFieldTarget.classList.toggle("hidden", mode !== "adjust_set");
    this.bufferFieldTarget.classList.remove("hidden");
  }

  openAdjustModal(event) {
    const skuId = Number(event.currentTarget.dataset.skuId);
    const sku = this.currentSkus.find((item) => item.id === skuId);
    if (!sku) return;

    this.adjustSkuIdTarget.value = sku.id;
    this.adjustSkuSummaryTarget.textContent =
      `${sku.code} • OnHand ${sku.on_hand ?? 0} • Reserved ${sku.reserved ?? 0} • Store ${sku.store_available ?? 0} • Online ${sku.online_available ?? 0}` +
      (sku.frozen ? ` • Frozen (${sku.freeze_reason || "-"})` : "");

    this.adjustModeTarget.value = "stock_in";
    this.quantityInputTarget.value = 1;
    this.deltaInputTarget.value = 0;
    this.setToInputTarget.value = sku.store_available ?? 0;
    this.bufferInputTarget.value = sku.buffer_quantity ?? 0;
    this.reasonInputTarget.value = "";
    this.noteInputTarget.value = "";
    this.hideAdjustMessage();
    this.onAdjustModeChange();
    this.updateAdjustWarning();

    this.modalBackdropTarget.classList.remove("hidden");
    this.adjustModalTarget.classList.remove("hidden");
  }

  async submitAdjust(event) {
    event.preventDefault();

    const submitBtn = event.target.querySelector("button[type='submit']");
    const originalText = submitBtn ? submitBtn.textContent : "";

    if (submitBtn) {
      submitBtn.disabled = true;
      submitBtn.textContent = "Processing...";
    }

    const skuId = this.adjustSkuIdTarget.value;
    if (!skuId) {
      if (submitBtn) {
        submitBtn.disabled = false;
        submitBtn.textContent = originalText;
      }
      return;
    }

    const mode = this.adjustModeTarget.value;
    const payload = {
      sku_id: skuId,
      mode,
      idempotency_key: this.generateIdempotencyKey(),
      buffer_quantity: Number(this.bufferInputTarget.value || 0),
    };

    if (mode === "stock_in") {
      payload.quantity = Number(this.quantityInputTarget.value || 0);
    }
    if (mode === "adjust_delta") {
      payload.delta = Number(this.deltaInputTarget.value || 0);
    }
    if (mode === "adjust_set") {
      payload.set_to = Number(this.setToInputTarget.value || 0);
    }
    if (mode === "update_buffer") {
      // send only buffer_quantity
    }

    if (this.reasonInputTarget.value.trim() !== "") {
      payload.reason = this.reasonInputTarget.value.trim();
    }
    if (this.noteInputTarget.value.trim() !== "") {
      payload.note = this.noteInputTarget.value.trim();
    }

    try {
      const response = await fetch("/pos/stock_adjust", {
        method: "POST",
        headers: this.jsonHeaders({
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken(),
        }),
        body: JSON.stringify(payload),
      });

      const data = await this.parseJsonResponse(
        response,
        "submitAdjust /pos/stock_adjust",
      );

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Adjust stock failed");
      }

      this.showAdjustMessage("success", "ปรับสต็อกสำเร็จ");
      await this.loadSkus();

      if (
        this.currentLedgerSkuId &&
        Number(this.currentLedgerSkuId) === Number(skuId)
      ) {
        await this.loadLedger(skuId);
      }

      setTimeout(() => this.closeAdjustModal(), 500);
    } catch (error) {
      console.error("submitAdjust error", error);
      this.showAdjustMessage("error", error.message);
    } finally {
      if (submitBtn) {
        submitBtn.disabled = false;
        submitBtn.textContent = originalText;
      }
    }
  }

  async openLedger(event) {
    const skuId = Number(event.currentTarget.dataset.skuId);
    await this.loadLedger(skuId);
  }

  async loadLedger(skuId) {
    const sku = this.currentSkus.find((item) => item.id === Number(skuId));
    this.currentLedgerSkuId = skuId;

    this.ledgerDrawerTarget.classList.add("is-open");
    this.ledgerListTarget.innerHTML = `<div class="ledger-loading">Loading...</div>`;
    this.ledgerEmptyTarget.style.display = "none";

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
      const skuData = data.sku;

      this.ledgerSkuSummaryTarget.textContent = `${skuData.code} • Store ${skuData.store_available} • Online ${skuData.online_available}`;

      if (ledger.length === 0) {
        this.ledgerListTarget.innerHTML = "";
        this.ledgerEmptyTarget.style.display = "block";
        this.ledgerEmptyTarget.textContent = "ยังไม่มี ledger entries";
        return;
      }

      this.ledgerListTarget.innerHTML = ledger
        .map((entry) => this.renderLedgerEntry(entry))
        .join("");
    } catch (error) {
      console.error("loadLedger error", error);
      this.ledgerListTarget.innerHTML = `<div class="ledger-error">โหลด ledger ไม่สำเร็จ</div>`;
    }
  }

  closeLedger() {
    this.ledgerDrawerTarget.classList.remove("is-open");
    this.currentLedgerSkuId = null;
  }

  renderLedgerEntry(entry) {
    const title =
      entry.source_type === "inventory_action"
        ? entry.action_type || "inventory_action"
        : entry.reason || "stock_movement";

    const delta = entry.delta_on_hand == null ? "-" : entry.delta_on_hand;
    const quantity = entry.quantity == null ? "-" : entry.quantity;
    const meta = this.escapeHtml(JSON.stringify(entry.meta || {}, null, 2));

    const shortfall =
      entry.meta?.shortfall != null
        ? `<span class="ledger-badge ledger-badge--warn">Shortfall ${entry.meta.shortfall}</span>`
        : "";

    const adjustMode = entry.meta?.adjust_mode
      ? `<span class="ledger-badge">${entry.meta.adjust_mode}</span>`
      : "";

    return `
      <article class="ledger-entry">
        <div class="ledger-entry__top">
          <div>
            <div class="ledger-entry__title">${this.escapeHtml(title)}</div>
            <div class="ledger-entry__sub">
              ${this.escapeHtml(entry.source_type || "-")} • ${this.escapeHtml(entry.occurred_at || "-")}
            </div>
          </div>
          <div class="ledger-entry__delta">Δ ${this.escapeHtml(String(delta))}</div>
        </div>

        <div class="ledger-entry__meta-row">
          <span>Qty: ${this.escapeHtml(String(quantity))}</span>
          <span>ID: ${this.escapeHtml(String(entry.id || "-"))}</span>
          ${shortfall}
          ${adjustMode}
        </div>

        ${
          entry.idempotency_key
            ? `
          <div class="ledger-entry__idempotency">
            ${this.escapeHtml(entry.idempotency_key)}
          </div>
        `
            : ""
        }

        <details class="ledger-entry__details">
          <summary>Meta</summary>
          <pre>${meta}</pre>
        </details>
      </article>
    `;
  }

  populateSelect(selectElement, values, currentValue, placeholder) {
    const safeValues = Array.isArray(values) ? values : [];
    const options = [
      `<option value="">${this.escapeHtml(placeholder)}</option>`,
    ];

    safeValues.forEach((value) => {
      const selected = String(value) === String(currentValue) ? "selected" : "";
      options.push(
        `<option value="${this.escapeAttribute(value)}" ${selected}>${this.escapeHtml(value)}</option>`,
      );
    });

    selectElement.innerHTML = options.join("");

    if (currentValue && !safeValues.includes(currentValue)) {
      selectElement.value = "";
    }
  }

  filtersForRequest() {
    const params = {
      limit: this.limitSelectTarget.value,
    };

    if (this.qInputTarget.value.trim() !== "") {
      params.q = this.qInputTarget.value.trim();
    }
    if (this.brandSelectTarget.value !== "") {
      params.brand = this.brandSelectTarget.value;
    }
    if (this.modelSelectTarget.value !== "") {
      params.model = this.modelSelectTarget.value;
    }
    if (this.colorSelectTarget.value !== "") {
      params.color = this.colorSelectTarget.value;
    }
    if (this.sizeSelectTarget.value !== "") {
      params.size = this.sizeSelectTarget.value;
    }

    params.active_only =
      this.statusSelectTarget.value === "active" ? "true" : "false";

    return params;
  }

  csrfToken() {
    const element = document.querySelector('meta[name="csrf-token"]');
    return element ? element.content : "";
  }

  posKey() {
    const element = document.querySelector('meta[name="pos-key"]');
    return element ? element.content : "";
  }

  jsonHeaders(extra = {}) {
    return {
      Accept: "application/json",
      "X-POS-KEY": this.posKey(),
      ...extra,
    };
  }

  humanFileSize(bytes) {
    const value = Number(bytes || 0);

    if (value < 1024) return `${value} B`;
    if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;

    return `${(value / (1024 * 1024)).toFixed(2)} MB`;
  }

  generateIdempotencyKey() {
    return `ui:stock_adjust:${Date.now()}:${Math.random().toString(36).slice(2, 10)}`;
  }

  showAdjustMessage(type, text) {
    this.adjustMessageTarget.textContent = text;
    this.adjustMessageTarget.classList.remove(
      "hidden",
      "is-error",
      "is-success",
    );
    this.adjustMessageTarget.classList.add(
      type === "error" ? "is-error" : "is-success",
    );
  }

  hideAdjustMessage() {
    this.adjustMessageTarget.textContent = "";
    this.adjustMessageTarget.classList.add("hidden");
    this.adjustMessageTarget.classList.remove("is-error", "is-success");
  }

  updateAdjustWarning() {
    const skuId = Number(this.adjustSkuIdTarget.value);
    const sku = this.currentSkus.find((s) => s.id === skuId);
    if (!sku) return;

    const mode = this.adjustModeTarget.value;

    let message = null;

    if (mode === "adjust_set") {
      const setTo = Number(this.setToInputTarget.value || 0);
      if (setTo < (sku.reserved ?? 0)) {
        message = "⚠️ Set stock ต่ำกว่า reserved → จะเกิด oversell และ freeze";
      }
    }

    if (mode === "adjust_delta") {
      const delta = Number(this.deltaInputTarget.value || 0);
      const newOnHand = (sku.on_hand ?? 0) + delta;
      if (newOnHand < (sku.reserved ?? 0)) {
        message = "⚠️ Delta นี้จะทำให้ stock ต่ำกว่า reserved → oversell";
      }
    }

    if (mode === "update_buffer" && sku.frozen) {
      message =
        "ℹ️ เปลี่ยน buffer อาจทำให้ auto-unfreeze (ถ้าไม่ใช่ manual freeze)";
    }

    if (message) {
      this.adjustWarningTarget.textContent = message;
      this.adjustWarningTarget.classList.remove("hidden");
      this.adjustWarningTarget.classList.add("is-error");
    } else {
      this.adjustWarningTarget.classList.add("hidden");
    }
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
