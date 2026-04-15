import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "brand",
    "model",
    "color",
    "size",
    "barcodeStatus",
    "barcodeInput",
    "message",
    "file",
    "fileName",
    "skuInfo",
    "bindButton",
    "uploadButton",
    "bulkResult",
    "bulkMessage",
  ];

  connect() {
    this.selectedSku = null;
    this.currentSkus = [];
    this.isBinding = false;
    this.isUploading = false;
    this.isLoadingSku = false;
    this.isClearing = false;

    this.loadInitialState();
  }

  async loadInitialState() {
    this.hideSingleMessage();
    this.hideBulkMessage();
    await this.loadFacets();
    await this.loadSku();
    this.focusBarcodeInput();
  }

  async onFilterChange() {
    this.hideSingleMessage();
    await this.loadFacets();
    await this.loadSku();
    this.focusBarcodeInput();
  }

  onFileChange() {
    const file = this.fileTarget.files[0];

    if (!file) {
      if (this.hasFileNameTarget) {
        this.fileNameTarget.textContent = "เลือกไฟล์สำหรับ bulk bind barcode";
      }
      return;
    }

    if (this.hasFileNameTarget) {
      this.fileNameTarget.textContent = file.name;
    }

    this.hideBulkMessage();
  }

  async onScanKeydown(event) {
    if (event.key !== "Enter") return;
    event.preventDefault();
    await this.bind();
  }

  async bind() {
    if (this.isBinding) return;

    this.hideSingleMessage();

    if (!this.selectedSku) {
      this.showSingleMessage("error", "Please select SKU first");
      return;
    }

    if (this.selectedSku.barcode_bound) {
      this.showSingleMessage(
        "error",
        `SKU already has barcode: ${this.selectedSku.barcode || "-"}`,
      );
      this.focusBarcodeInput();
      return;
    }

    const barcode = this.normalizeBarcode(this.barcodeInputTarget.value);
    if (!barcode) {
      this.showSingleMessage("error", "Please scan or enter barcode");
      this.focusBarcodeInput();
      return;
    }

    this.isBinding = true;
    this.setBindButtonState(true, "Binding...");
    this.showSingleMessage("loading", "Binding barcode...");

    try {
      const response = await fetch("/pos/barcode_bindings", {
        method: "POST",
        headers: this.jsonHeaders({
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken(),
        }),
        body: JSON.stringify({
          sku_id: this.selectedSku.id,
          barcode,
        }),
      });

      const data = await this.parseJsonResponse(
        response,
        "bind /pos/barcode_bindings",
      );

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Bind failed");
      }

      this.barcodeInputTarget.value = "";
      this.showSingleMessage(
        "success",
        `Bind success: ${data.sku?.code || this.selectedSku.code} → ${data.sku?.barcode || barcode}`,
      );

      await this.loadSku();
      this.focusBarcodeInput();
    } catch (error) {
      console.error("barcode bind failed", error);
      this.showSingleMessage("error", error.message || "Bind failed");
      this.focusBarcodeInput();
    } finally {
      this.isBinding = false;
      this.setBindButtonState(false, "Bind");
    }
  }

  async clearBarcode() {
    if (this.isClearing) return;

    this.hideSingleMessage();

    if (!this.selectedSku) {
      this.showSingleMessage("error", "Please select SKU first");
      return;
    }

    if (!this.selectedSku.barcode_bound) {
      this.showSingleMessage("error", "This SKU already has no barcode");
      return;
    }

    const confirmed = window.confirm(
      `Clear barcode for ${this.selectedSku.code} ?`,
    );
    if (!confirmed) return;

    this.isClearing = true;
    this.showSingleMessage("loading", "Clearing barcode...");

    try {
      const response = await fetch("/ops/barcode_bindings/clear", {
        method: "POST",
        headers: this.jsonHeaders({
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken(),
        }),
        body: JSON.stringify({
          sku_id: this.selectedSku.id,
        }),
      });

      const data = await this.parseJsonResponse(
        response,
        "clearBarcode /ops/barcode_bindings/clear",
      );

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Clear barcode failed");
      }

      this.barcodeInputTarget.value = "";
      this.showSingleMessage(
        "success",
        `Barcode cleared: ${data.sku?.code || this.selectedSku.code}`,
      );

      await this.loadSku();
      this.focusBarcodeInput();
    } catch (error) {
      console.error("clear barcode failed", error);
      this.showSingleMessage("error", error.message || "Clear barcode failed");
    } finally {
      this.isClearing = false;
    }
  }

  async upload() {
    if (this.isUploading) return;

    const file = this.fileTarget.files[0];
    this.hideBulkMessage();

    if (!file) {
      this.showBulkMessage("error", "Please choose a CSV file");
      return;
    }

    const formData = new FormData();
    formData.append("file", file);

    this.isUploading = true;
    this.setUploadButtonState(true, "Uploading...");
    this.showBulkMessage("loading", "Uploading CSV...");

    if (this.hasBulkResultTarget) {
      this.bulkResultTarget.innerHTML = "";
      this.bulkResultTarget.classList.add("hidden");
    }

    try {
      const response = await fetch("/ops/barcode_bindings/import", {
        method: "POST",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": this.csrfToken(),
        },
        body: formData,
      });

      const data = await this.parseJsonResponse(
        response,
        "upload /ops/barcode_bindings/import",
      );

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Upload failed");
      }

      this.renderBulkResult(data.result);
      this.showBulkMessage("success", "CSV import completed");
      await this.loadSku();

      this.fileTarget.value = "";
      if (this.hasFileNameTarget) {
        this.fileNameTarget.textContent = "เลือกไฟล์สำหรับ bulk bind barcode";
      }

      this.focusBarcodeInput();
    } catch (error) {
      console.error("barcode import failed", error);
      this.showBulkMessage("error", error.message || "Upload failed");
    } finally {
      this.isUploading = false;
      this.setUploadButtonState(false, "Upload CSV");
    }
  }

  async loadFacets() {
    try {
      const response = await fetch(
        `/pos/skus/facets?${new URLSearchParams(this.filtersForRequest()).toString()}`,
        { headers: this.jsonHeaders() },
      );

      const data = await this.parseJsonResponse(
        response,
        "loadFacets /pos/skus/facets",
      );

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Failed to load filters");
      }

      this.populateSelect(this.brandTarget, data.facets?.brands || [], "All");
      this.populateSelect(this.modelTarget, data.facets?.models || [], "All");
      this.populateSelect(this.colorTarget, data.facets?.colors || [], "All");
      this.populateSelect(this.sizeTarget, data.facets?.sizes || [], "All");
    } catch (error) {
      console.error("loadFacets failed", error);
      this.showSingleMessage(
        "error",
        error.message || "Failed to load filters",
      );
    }
  }

  async loadSku() {
    this.isLoadingSku = true;
    this.renderSkuInfoLoading();

    try {
      const response = await fetch(
        `/pos/skus/search?${new URLSearchParams(this.filtersForRequest()).toString()}`,
        { headers: this.jsonHeaders() },
      );

      const data = await this.parseJsonResponse(
        response,
        "loadSku /pos/skus/search",
      );

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Failed to load SKU");
      }

      let skus = Array.isArray(data.skus) ? data.skus : [];
      skus = this.applyBarcodeStatusFilter(skus);

      this.currentSkus = skus;

      if (this.currentSkus.length === 0) {
        this.selectedSku = null;
        this.renderNoSku();
        return;
      }

      if (this.currentSkus.length === 1) {
        this.selectedSku = this.currentSkus[0];
        this.renderSelectedSku();
        return;
      }

      const exactMatch = this.currentSkus.find((sku) => {
        return (
          String(sku.brand || "") === String(this.brandTarget.value || "") &&
          String(sku.model || "") === String(this.modelTarget.value || "") &&
          String(sku.color || "") === String(this.colorTarget.value || "") &&
          String(sku.size || "") === String(this.sizeTarget.value || "")
        );
      });

      this.selectedSku = exactMatch || null;

      if (this.selectedSku) {
        this.renderSelectedSku();
      } else {
        this.renderMultipleSkuHint(this.currentSkus);
      }
    } catch (error) {
      console.error("loadSku failed", error);
      this.selectedSku = null;
      this.renderSkuError(error.message || "Failed to load SKU");
    } finally {
      this.isLoadingSku = false;
    }
  }

  applyBarcodeStatusFilter(skus) {
    const mode = this.hasBarcodeStatusTarget
      ? this.barcodeStatusTarget.value
      : "all";

    if (mode === "needs_binding") {
      return skus.filter((sku) => !sku.barcode_bound);
    }

    if (mode === "bound") {
      return skus.filter((sku) => sku.barcode_bound);
    }

    return skus;
  }

  selectSku(event) {
    const skuId = Number(event.currentTarget.dataset.skuId);
    const sku = this.currentSkus.find((item) => Number(item.id) === skuId);
    if (!sku) return;

    this.selectedSku = sku;
    this.hideSingleMessage();
    this.renderSelectedSku();
    this.focusBarcodeInput();
  }

  clearSelectedSku() {
    this.selectedSku = null;
    this.barcodeInputTarget.value = "";
    this.hideSingleMessage();
    this.renderMultipleSkuHint(this.currentSkus || []);
    this.focusBarcodeInput();
  }

  renderSelectedSku() {
    const sku = this.selectedSku;
    if (!sku) {
      this.renderNoSku();
      return;
    }

    const barcodeStatus = sku.barcode_bound
      ? `<span class="ui-pill ui-pill--status is-active">Bound</span>`
      : `<span class="ui-pill ui-pill--status is-inactive">Needs binding</span>`;

    const clearButton = sku.barcode_bound
      ? `
        <button
          type="button"
          class="btn btn-danger btn-sm"
          data-action="click->barcode-binding#clearBarcode">
          Clear Barcode
        </button>
      `
      : "";

    this.skuInfoTarget.innerHTML = `
      <div class="barcode-binding-sku-card">
        <div class="barcode-binding-sku-card__top">
          <div>
            <div class="barcode-binding-sku-card__code">${this.escapeHtml(sku.code || "-")}</div>
          </div>

          <div class="barcode-binding-sku-card__top-actions">
            ${barcodeStatus}
            ${clearButton}
            <button
              type="button"
              class="btn btn-secondary btn-sm"
              data-action="click->barcode-binding#clearSelectedSku">
              Back
            </button>
          </div>
        </div>

        <div class="barcode-binding-sku-card__details">
          <div><strong>Barcode:</strong> ${this.escapeHtml(sku.barcode || "-")}</div>
          <div><strong>Store:</strong> ${this.escapeHtml(String(sku.store_available ?? 0))}</div>
          <div><strong>Online:</strong> ${this.escapeHtml(String(sku.online_available ?? 0))}</div>
        </div>
      </div>
    `;
  }

  renderMultipleSkuHint(skus) {
    this.skuInfoTarget.innerHTML = `
      <div class="barcode-binding-sku-list">
        <div class="barcode-binding-sku-list__title">
          Found ${this.escapeHtml(String(skus.length))} SKU(s)
        </div>

        <div class="barcode-binding-sku-list__subtitle">
          Please select one SKU before binding
        </div>

        <div class="barcode-binding-sku-list__items">
          ${skus
            .slice(0, 20)
            .map(
              (sku) => `
                <button
                  type="button"
                  class="barcode-binding-sku-list__item"
                  data-action="click->barcode-binding#selectSku"
                  data-sku-id="${sku.id}">
                  <div class="barcode-binding-sku-list__code">${this.escapeHtml(sku.code || "-")}</div>
                  <div class="barcode-binding-sku-list__status">
                    ${sku.barcode_bound ? "Bound" : "Needs binding"}
                  </div>
                  <div class="barcode-binding-sku-list__barcode">
                    Barcode: ${this.escapeHtml(sku.barcode || "-")}
                  </div>
                </button>
              `,
            )
            .join("")}
        </div>
      </div>
    `;
  }

  renderNoSku() {
    this.skuInfoTarget.innerHTML = `
      <div class="barcode-binding-empty">
        No SKU found for current filters
      </div>
    `;
  }

  renderSkuInfoLoading() {
    this.skuInfoTarget.innerHTML = `
      <div class="barcode-binding-empty">
        Loading SKU...
      </div>
    `;
  }

  renderSkuError(message) {
    this.skuInfoTarget.innerHTML = `
      <div class="barcode-binding-empty is-error">
        ${this.escapeHtml(message)}
      </div>
    `;
  }

  renderBulkResult(result) {
    if (!this.hasBulkResultTarget) return;

    const items = [
      ["Rows", result.total_rows ?? 0],
      ["Success", result.success_rows ?? 0],
      ["Failed", result.failed_rows ?? 0],
      ["Blank", result.blank_rows ?? 0],
      ["Duplicate in file", result.duplicate_rows_in_file ?? 0],
    ];

    const errorSamples = Array.isArray(result.error_samples)
      ? result.error_samples
      : [];

    this.bulkResultTarget.innerHTML = `
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

      ${
        errorSamples.length > 0
          ? `
            <div class="barcode-binding-errors">
              <div class="barcode-binding-errors__title">Sample errors</div>
              <div class="barcode-binding-errors__list">
                ${errorSamples
                  .slice(0, 10)
                  .map(
                    (item) => `
                      <div class="barcode-binding-errors__item">
                        Row ${this.escapeHtml(String(item.row ?? "-"))}
                        • SKU ${this.escapeHtml(item.sku || "-")}
                        • ${this.escapeHtml(item.error || "Error")}
                      </div>
                    `,
                  )
                  .join("")}
              </div>
            </div>
          `
          : ""
      }
    `;

    this.bulkResultTarget.classList.remove("hidden");
  }

  populateSelect(selectElement, values, placeholder) {
    const currentValue = selectElement.value;
    const safeValues = Array.isArray(values) ? values : [];

    selectElement.innerHTML = [
      `<option value="">${this.escapeHtml(placeholder)}</option>`,
      ...safeValues.map((value) => {
        const selected =
          String(value) === String(currentValue) ? "selected" : "";
        return `<option value="${this.escapeAttribute(value)}" ${selected}>${this.escapeHtml(value)}</option>`;
      }),
    ].join("");

    if (currentValue && !safeValues.includes(currentValue)) {
      selectElement.value = "";
    }
  }

  filtersForRequest() {
    const params = {
      active_only: "true",
      limit: "50",
    };

    if (this.brandTarget.value) params.brand = this.brandTarget.value;
    if (this.modelTarget.value) params.model = this.modelTarget.value;
    if (this.colorTarget.value) params.color = this.colorTarget.value;
    if (this.sizeTarget.value) params.size = this.sizeTarget.value;

    return params;
  }

  setBindButtonState(disabled, text) {
    if (!this.hasBindButtonTarget) return;
    this.bindButtonTarget.disabled = disabled;
    this.bindButtonTarget.textContent = text;
  }

  setUploadButtonState(disabled, text) {
    if (!this.hasUploadButtonTarget) return;
    this.uploadButtonTarget.disabled = disabled;
    this.uploadButtonTarget.textContent = text;
  }

  showSingleMessage(type, text) {
    if (!this.hasMessageTarget) return;

    this.messageTarget.textContent = text;
    this.messageTarget.classList.remove(
      "hidden",
      "is-error",
      "is-success",
      "is-loading",
    );

    if (type === "error") this.messageTarget.classList.add("is-error");
    if (type === "success") this.messageTarget.classList.add("is-success");
    if (type === "loading") this.messageTarget.classList.add("is-loading");
  }

  hideSingleMessage() {
    if (!this.hasMessageTarget) return;

    this.messageTarget.textContent = "";
    this.messageTarget.classList.add("hidden");
    this.messageTarget.classList.remove("is-error", "is-success", "is-loading");
  }

  showBulkMessage(type, text) {
    if (!this.hasBulkMessageTarget) return;

    this.bulkMessageTarget.textContent = text;
    this.bulkMessageTarget.classList.remove(
      "hidden",
      "is-error",
      "is-success",
      "is-loading",
    );

    if (type === "error") this.bulkMessageTarget.classList.add("is-error");
    if (type === "success") this.bulkMessageTarget.classList.add("is-success");
    if (type === "loading") this.bulkMessageTarget.classList.add("is-loading");
  }

  hideBulkMessage() {
    if (!this.hasBulkMessageTarget) return;

    this.bulkMessageTarget.textContent = "";
    this.bulkMessageTarget.classList.add("hidden");
    this.bulkMessageTarget.classList.remove(
      "is-error",
      "is-success",
      "is-loading",
    );
  }

  focusBarcodeInput() {
    if (!this.hasBarcodeInputTarget) return;

    window.requestAnimationFrame(() => {
      this.barcodeInputTarget.focus();
      if (typeof this.barcodeInputTarget.select === "function") {
        this.barcodeInputTarget.select();
      }
    });
  }

  normalizeBarcode(value) {
    return String(value || "")
      .replace(/\s+/g, "")
      .trim();
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
