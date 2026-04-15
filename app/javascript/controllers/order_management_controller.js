import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "qInput",
    "statusSelect",
    "shopSelect",
    "dateFromInput",
    "dateToInput",
    "limitSelect",
    "resultSummary",
    "orderList",
    "exportPackingButton",
    "exportButton",
  ];

  connect() {
    this.searchDebounce = null;
    this.loadOrders();
  }

  refreshOrders() {
    this.loadOrders();
  }

  onFilterInput() {
    clearTimeout(this.searchDebounce);
    this.searchDebounce = setTimeout(() => {
      this.loadOrders();
    }, 300);
  }

  onFilterChange() {
    this.loadOrders();
  }

  resetFilters() {
    this.qInputTarget.value = "";
    this.statusSelectTarget.value = "";
    this.shopSelectTarget.value = "";
    this.dateFromInputTarget.value = "";
    this.dateToInputTarget.value = "";
    this.limitSelectTarget.value = "50";

    this.loadOrders();
  }

  async loadOrders() {
    this.resultSummaryTarget.textContent = "Loading...";
    this.orderListTarget.innerHTML = `<div class="table-empty">Loading...</div>`;

    try {
      const response = await fetch(
        `/ops/orders?${new URLSearchParams(this.filtersForRequest()).toString()}`,
        {
          headers: { Accept: "application/json" },
        },
      );

      const contentType = response.headers.get("content-type") || "";

      let data;

      if (contentType.includes("application/json")) {
        data = await response.json();
      } else {
        const text = await response.text();

        console.error("Non-JSON response from /ops/orders", {
          status: response.status,
          body: text.slice(0, 500),
        });

        throw new Error(`Expected JSON but got: ${contentType || "unknown"}`);
      }

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Failed to load orders");
      }

      const orders = Array.isArray(data.orders) ? data.orders : [];
      this.resultSummaryTarget.textContent = `Found ${data.count} order(s)`;

      if (orders.length === 0) {
        this.orderListTarget.innerHTML = `<div class="table-empty">ไม่พบออเดอร์</div>`;
        return;
      }

      this.orderListTarget.innerHTML = orders
        .map((order) => this.renderOrderCard(order))
        .join("");
    } catch (error) {
      console.error("loadOrders error", error);

      this.resultSummaryTarget.textContent = "Load failed";
      this.orderListTarget.innerHTML = `<div class="table-empty">โหลดข้อมูลไม่สำเร็จ</div>`;
    }
  }

  exportPacking() {
    const btn = this.exportPackingButtonTarget;
    const originalText = btn.textContent;

    btn.disabled = true;
    btn.textContent = "Exporting...";

    try {
      const params = new URLSearchParams(this.filtersForExport()).toString();
      const url = `/ops/orders/export_packing_sheet?${params}`;

      window.location.href = url;
    } catch (_error) {
      alert("Export failed");
      btn.disabled = false;
      btn.textContent = originalText;
    }

    setTimeout(() => {
      btn.disabled = false;
      btn.textContent = originalText;
    }, 1000);
  }

  async exportOrders() {
    const originalText = this.exportButtonTarget.textContent;

    this.exportButtonTarget.disabled = true;
    this.exportButtonTarget.textContent = "Exporting...";

    try {
      const params = new URLSearchParams(this.filtersForExport()).toString();
      const url = `/ops/orders/export_shipping_sheet?${params}`;

      const response = await fetch(url, {
        method: "POST",
        headers: {
          Accept:
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        },
      });

      const contentType = response.headers.get("content-type") || "";

      if (!response.ok) {
        let errorMessage = "Export failed";

        if (contentType.includes("application/json")) {
          const data = await response.json();
          errorMessage = data.message || data.error || errorMessage;
        } else {
          errorMessage = await response.text();
        }

        throw new Error(errorMessage);
      }

      const blob = await response.blob();

      if (
        !contentType.includes(
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )
      ) {
        throw new Error("Server did not return an Excel file");
      }

      const disposition = response.headers.get("content-disposition") || "";
      const filename =
        this.extractFilenameFromDisposition(disposition) ||
        "shipping_export.xlsx";

      const blobUrl = window.URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = blobUrl;
      link.download = filename;
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.URL.revokeObjectURL(blobUrl);
    } catch (error) {
      console.error("exportOrders error", error);
      window.alert(`Export failed: ${error.message}`);
    } finally {
      this.exportButtonTarget.disabled = false;
      this.exportButtonTarget.textContent = originalText;
    }
  }

  filtersForRequest() {
    const params = {
      limit: this.limitSelectTarget.value,
    };

    if (this.qInputTarget.value.trim() !== "") {
      params.q = this.qInputTarget.value.trim();
    }
    if (this.statusSelectTarget.value !== "") {
      params.status = this.statusSelectTarget.value;
    }
    if (this.shopSelectTarget.value !== "") {
      params.shop = this.shopSelectTarget.value;
    }
    if (this.dateFromInputTarget.value !== "") {
      params.date_from = this.dateFromInputTarget.value;
    }
    if (this.dateToInputTarget.value !== "") {
      params.date_to = this.dateToInputTarget.value;
    }

    return params;
  }

  filtersForExport() {
    const params = {};

    if (this.qInputTarget.value.trim() !== "") {
      params.q = this.qInputTarget.value.trim();
    }

    if (this.statusSelectTarget.value !== "") {
      params.status = this.statusSelectTarget.value;
    }

    if (this.shopSelectTarget.value !== "") {
      params.shop = this.shopSelectTarget.value;
    }

    if (this.dateFromInputTarget.value !== "") {
      params.date_from = this.dateFromInputTarget.value;
    }

    if (this.dateToInputTarget.value !== "") {
      params.date_to = this.dateToInputTarget.value;
    }

    return params;
  }

  extractFilenameFromDisposition(disposition) {
    if (!disposition) return null;

    const utf8Match = disposition.match(/filename\*=UTF-8''([^;]+)/i);
    if (utf8Match && utf8Match[1]) {
      return decodeURIComponent(utf8Match[1]);
    }

    const asciiMatch = disposition.match(/filename="([^"]+)"/i);
    if (asciiMatch && asciiMatch[1]) {
      return asciiMatch[1];
    }

    return null;
  }

  renderOrderCard(order) {
    const lines = Array.isArray(order.lines) ? order.lines : [];

    const linesHtml =
      lines.length > 0
        ? lines
            .map(
              (line) => `
            <div class="order-item">
              <div class="order-item__sku">${this.escapeHtml(line.sku_code || "-")}</div>
              <div class="order-item__qty">x${this.escapeHtml(String(line.quantity ?? 0))}</div>
            </div>
          `,
            )
            .join("")
        : `
            <div class="order-item">
              <div class="order-item__sku">-</div>
              <div class="order-item__qty">-</div>
            </div>
          `;

    const topTags = [
      this.renderTopTag("shop", order.display_shop),
      this.renderTopTag("status", order.status),
      this.renderTopTag("logistic", order.logistic_provider),
      this.renderTopTag("time", this.formatDateTime(order.ordered_at)),
    ]
      .filter(Boolean)
      .join("");

    return `
      <article class="market-order-card">
        <div class="market-order-card__top">
          <div class="market-order-card__identity">
            <div class="market-order-card__label">Order Number</div>
            <div class="market-order-card__number">${this.escapeHtml(order.order_number || "-")}</div>
          </div>

          <div class="market-order-card__badges">
            ${topTags}
          </div>
        </div>

        <div class="market-order-card__content market-order-card__content--single">
          <div class="market-order-card__left">
            <div class="market-order-card__section-title">Items</div>
            <div class="market-order-card__items">
              ${linesHtml}
            </div>
          </div>
        </div>

        <div class="market-order-card__bottom-grid">
          <div class="market-meta">
            <div class="market-meta__label">Tracking Number</div>
            <div class="market-meta__value">${this.displayValue(order.tracking_number)}</div>
          </div>

          <div class="market-meta">
            <div class="market-meta__label">Buyer Message</div>
            <div class="market-meta__value">${this.displayValue(order.buyer_message)}</div>
          </div>
        </div>
      </article>
    `;
  }

  renderTopTag(type, value) {
    if (
      value === null ||
      value === undefined ||
      String(value).trim() === "" ||
      String(value).trim() === "-"
    ) {
      return "";
    }

    return `<span class="market-pill market-pill--${this.escapeHtml(type)}">${this.escapeHtml(String(value))}</span>`;
  }

  displayValue(value) {
    if (value === null || value === undefined || String(value).trim() === "") {
      return "-";
    }

    return this.escapeHtml(String(value));
  }

  formatDateTime(value) {
    if (value === null || value === undefined || String(value).trim() === "") {
      return "-";
    }

    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return this.escapeHtml(String(value));
    }

    const day = String(date.getDate()).padStart(2, "0");
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const year = date.getFullYear();
    const hours = date.getHours();
    const minutes = String(date.getMinutes()).padStart(2, "0");
    const seconds = String(date.getSeconds()).padStart(2, "0");

    return `${day}/${month}/${year} ${hours}:${minutes}:${seconds}`;
  }

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }
}
