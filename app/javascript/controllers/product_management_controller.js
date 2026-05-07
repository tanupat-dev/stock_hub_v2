import { Controller } from "@hotwired/stimulus";
import { productManagementLedgerMethods } from "controllers/product_management/ledger";
import { productManagementImportMethods } from "controllers/product_management/import_modal";
import { productManagementTableMethods } from "controllers/product_management/table";
import { productManagementAdjustMethods } from "controllers/product_management/adjust_modal";

class ProductManagementController extends Controller {
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

  async loadFacets() {
    try {
      const url = `/pos/skus/facets?${new URLSearchParams(
        this.filtersForRequest(),
      ).toString()}`;

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

  async openLedger(event) {
    const skuId = Number(event.currentTarget.dataset.skuId);
    await this.loadLedger(skuId);
  }

  populateSelect(selectElement, values, currentValue, placeholder) {
    const safeValues = Array.isArray(values) ? values : [];
    const options = [
      `<option value="">${this.escapeHtml(placeholder)}</option>`,
    ];

    safeValues.forEach((value) => {
      const selected = String(value) === String(currentValue) ? "selected" : "";

      options.push(
        `<option value="${this.escapeAttribute(value)}" ${selected}>${this.escapeHtml(
          value,
        )}</option>`,
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
    return `ui:stock_adjust:${Date.now()}:${Math.random()
      .toString(36)
      .slice(2, 10)}`;
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
      `Expected JSON response but got ${
        contentType || "unknown content type"
      } (status ${response.status})`,
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

Object.assign(
  ProductManagementController.prototype,
  productManagementLedgerMethods,
  productManagementImportMethods,
  productManagementTableMethods,
  productManagementAdjustMethods,
);

export default ProductManagementController;
