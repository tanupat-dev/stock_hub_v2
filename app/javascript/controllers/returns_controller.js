import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "qInput",
    "channelSelect",
    "shopSelect",
    "statusSelect",
    "limitSelect",
    "list",
    "summary",
  ];

  connect() {
    this.currentShipment = null;
    this.expandedShipmentId = null;
    this.shops = [];
    this.isFetchingList = false;
    this.scanLoading = false;
    this.lastRows = [];

    this.loadShops();
    this.fetchList();
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || "";
  }

  posKey() {
    return document.querySelector('meta[name="pos-key"]')?.content || "";
  }

  generateKey(prefix) {
    return `${prefix}:${Date.now()}:${Math.random().toString(16).slice(2, 8)}`;
  }

  async request(url, options = {}) {
    try {
      const response = await fetch(url, {
        method: options.method || "GET",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken(),
          "X-POS-KEY": this.posKey(),
          ...(options.headers || {}),
        },
        credentials: "same-origin",
        body: options.body,
      });

      const data = await response.json();

      if (!response.ok || data.ok === false) {
        throw new Error(data.error || "Request failed");
      }

      return data;
    } catch (e) {
      console.error("request error:", e);
      throw e;
    }
  }

  toast(message) {
    const el = document.createElement("div");
    el.className = "pos-toast";
    el.textContent = message;

    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2000);
  }

  async loadShops() {
    try {
      const data = await this.request("/ops/returns/shops");
      if (!data) return;

      this.shops = data.shops;
      this.renderShopOptions();
    } catch (e) {
      console.error("loadShops error", e);
    }
  }

  renderShopOptions() {
    if (!this.hasShopSelectTarget) return;

    const options = [
      `<option value="">All</option>`,
      ...this.shops.map(
        (s) => `<option value="${s.id}">${s.shop_code}</option>`,
      ),
    ];

    this.shopSelectTarget.innerHTML = options.join("");
  }

  filterShopByChannel() {
    if (!this.hasShopSelectTarget) return;

    const channel = this.channelSelectTarget.value;
    const currentSelectedShopId = this.shopSelectTarget.value;

    const filtered = channel
      ? this.shops.filter((s) => s.channel === channel)
      : this.shops;

    const selectedStillExists = filtered.some(
      (s) => String(s.id) === String(currentSelectedShopId),
    );

    const options = [
      `<option value="">All</option>`,
      ...filtered.map(
        (s) => `
          <option value="${s.id}" ${selectedStillExists && String(s.id) === String(currentSelectedShopId) ? "selected" : ""}>
            ${s.shop_code}
          </option>
        `,
      ),
    ];

    this.shopSelectTarget.innerHTML = options.join("");

    if (!selectedStillExists) {
      this.shopSelectTarget.value = "";
    }
  }

  buildQuery() {
    const params = new URLSearchParams();

    const q = this.qInputTarget.value.trim();

    if (q) {
      params.append("q", q);
    }

    if (this.channelSelectTarget.value) {
      params.append("channel", this.channelSelectTarget.value);
    }

    if (this.shopSelectTarget.value) {
      params.append("shop_id", this.shopSelectTarget.value);
    }

    if (this.statusSelectTarget.value) {
      params.append("status_store", this.statusSelectTarget.value);
    }

    if (this.limitSelectTarget.value) {
      params.append("limit", this.limitSelectTarget.value);
    }

    return params.toString();
  }

  onFilterInput() {
    clearTimeout(this.filterTimeout);
    this.filterTimeout = setTimeout(() => {
      this.expandedShipmentId = null;
      this.currentShipment = null;
      this.fetchList();
    }, 300);
  }

  onFilterChange() {
    this.filterShopByChannel();
    this.expandedShipmentId = null;
    this.currentShipment = null;
    this.fetchList();
  }

  resetFilters() {
    this.qInputTarget.value = "";
    this.channelSelectTarget.value = "";
    this.shopSelectTarget.value = "";
    this.statusSelectTarget.value = "";
    this.limitSelectTarget.value = "50";

    this.renderShopOptions();
    this.expandedShipmentId = null;
    this.currentShipment = null;
    this.fetchList();
  }

  refresh() {
    this.fetchList();
  }

  async fetchList() {
    if (this.isFetchingList) return;
    this.isFetchingList = true;

    this.listTarget.innerHTML = `<div class="table-empty">Loading...</div>`;

    try {
      const query = this.buildQuery();
      const data = await this.request(`/ops/return_shipments?${query}`);

      if (!data) return;

      this.summaryTarget.textContent = `${data.count} shipments`;
      this.lastRows = Array.isArray(data.return_shipments)
        ? data.return_shipments
        : [];
      this.renderList(this.lastRows);

      if (this.expandedShipmentId) {
        const stillExists = this.lastRows.some(
          (row) => String(row.id) === String(this.expandedShipmentId),
        );

        if (stillExists) {
          await this.loadExpandedDetail(this.expandedShipmentId, {
            preserveLoading: true,
          });
        } else {
          this.expandedShipmentId = null;
          this.currentShipment = null;
        }
      }
    } catch (e) {
      this.listTarget.innerHTML = `<div class="table-empty">${this.escapeHtml(e.message)}</div>`;
    } finally {
      this.isFetchingList = false;
    }
  }

  renderList(rows) {
    if (!rows.length) {
      this.listTarget.innerHTML = `<div class="table-empty">No data</div>`;
      return;
    }

    const html = rows.map((r) => this.renderShipmentCard(r)).join("");
    this.listTarget.innerHTML = `<div class="order-list">${html}</div>`;
  }

  renderShipmentCard(r) {
    const shipmentHint = this.shipmentHintFor(r);
    const trackingText = this.trackingTextFor(r);
    const requestedAt = this.formatDateTime(r.requested_at);
    const returnedAt = r.returned_delivered_at
      ? this.formatDateTime(r.returned_delivered_at)
      : "";
    const statusClass = this.statusClassFor(r.derived_status_store);
    const isExpanded = String(this.expandedShipmentId) === String(r.id);

    return `
      <div class="returns-card-wrap" data-shipment-wrap-id="${r.id}">
        <div class="market-order-card ${isExpanded ? "is-expanded" : ""}" data-id="${r.id}">
          <div class="market-order-card__top">
            <div>
              <div class="market-order-card__label">Return</div>
              <div class="market-order-card__number">${this.escapeHtml(r.external_return_id || "-")}</div>

              <div class="returns-dates">
                <div class="returns-date-chip returns-date-chip--request">
                  <span class="returns-date-chip__label">Requested</span>
                  <span class="returns-date-chip__value">${this.escapeHtml(requestedAt)}</span>
                </div>

                <div class="returns-date-chip returns-date-chip--returned ${returnedAt ? "" : "is-empty"}">
                  <span class="returns-date-chip__label">Returned</span>
                  <span class="returns-date-chip__value">${this.escapeHtml(returnedAt || "-")}</span>
                </div>
              </div>
            </div>

            <div class="market-order-card__badges">
              <span class="market-pill market-pill--channel">${this.escapeHtml(r.channel || "-")}</span>
              <span class="market-pill market-pill--shop">${this.escapeHtml(r.shop_code || "-")}</span>
              <span class="market-pill market-pill--status ${statusClass}">
                ${this.escapeHtml(this.humanizeStoreStatus(r.derived_status_store))}
              </span>
            </div>
          </div>

          <div class="market-order-card__content market-order-card__content--single">
            <div class="market-meta-grid">
              <div class="market-meta">
                <div class="market-meta__label">Order</div>
                <div class="market-meta__value">${this.escapeHtml(r.external_order_id || "-")}</div>
              </div>

              <div class="market-meta">
                <div class="market-meta__label">Buyer</div>
                <div class="market-meta__value">${this.escapeHtml(r.buyer_username || "-")}</div>
              </div>

              <div class="market-meta">
                <div class="market-meta__label">Carrier</div>
                <div class="market-meta__value">${this.escapeHtml(r.return_carrier_method || "-")}</div>
              </div>

              <div class="market-meta">
                <div class="market-meta__label">Tracking</div>
                <div class="market-meta__value">${this.escapeHtml(trackingText)}</div>
              </div>

              <div class="market-meta market-meta--wide">
                <div class="market-meta__label">Shipment Status</div>
                <div class="market-meta__value">${this.escapeHtml(shipmentHint)}</div>
              </div>

              <div class="market-meta">
                <div class="market-meta__label">Marketplace Status</div>
                <div class="market-meta__value">${this.escapeHtml(this.humanizeMarketplaceStatus(r.status_marketplace))}</div>
              </div>

              <div class="market-meta">
                <div class="market-meta__label">Qty</div>
                <div class="market-meta__value">${this.escapeHtml(`${r.total_qty_scanned} / ${r.total_qty_requested}`)}</div>
              </div>
            </div>
          </div>

          <div style="margin-top:12px;">
            <button
              class="btn btn-primary"
              data-action="click->returns#toggleDetail"
              data-id="${r.id}">
              ${isExpanded ? "Hide" : "View"}
            </button>
          </div>
        </div>

        <div class="returns-inline-detail-host" data-detail-host-id="${r.id}">
          ${isExpanded ? this.renderInlineLoading() : ""}
        </div>
      </div>
    `;
  }

  renderInlineLoading() {
    return `
      <section class="panel returns-inline-detail">
        <div class="table-empty">Loading...</div>
      </section>
    `;
  }

  async toggleDetail(e) {
    const id = e.currentTarget.dataset.id;

    if (String(this.expandedShipmentId) === String(id)) {
      this.expandedShipmentId = null;
      this.currentShipment = null;
      this.renderList(this.lastRows);
      return;
    }

    this.expandedShipmentId = id;
    this.currentShipment = null;

    this.renderList(this.lastRows);
    await this.loadExpandedDetail(id);
  }

  async loadExpandedDetail(id, options = {}) {
    const preserveLoading = options.preserveLoading === true;
    const host = this.findDetailHost(id);

    if (host && !preserveLoading) {
      host.innerHTML = this.renderInlineLoading();
    }

    try {
      const data = await this.request(`/ops/return_shipments/${id}`);
      if (!data) return;

      if (String(this.expandedShipmentId) !== String(id)) return;

      this.currentShipment = data.return_shipment;
      this.renderInlineDetail(data.return_shipment);
    } catch (e) {
      if (String(this.expandedShipmentId) !== String(id)) return;
      this.toast(e.message);
      this.renderInlineError(id, e.message);
    }
  }

  renderInlineError(id, message) {
    const host = this.findDetailHost(id);
    if (!host) return;

    host.innerHTML = `
      <section class="panel returns-inline-detail">
        <div class="table-empty">${this.escapeHtml(message)}</div>
      </section>
    `;
  }

  renderInlineDetail(shipment) {
    const host = this.findDetailHost(shipment.id);
    if (!host) return;

    const fullyScanned = this.isReceivedScanned(shipment);
    const scanHint = fullyScanned
      ? "Return receivedครบแล้ว ปิดการสแกน"
      : this.scanHintFor(shipment);

    const lineRows =
      Array.isArray(shipment.lines) && shipment.lines.length > 0
        ? shipment.lines
            .map((l) => {
              const lineStatus = l.fully_scanned ? "Done" : "Pending";
              const lineIdentifier =
                l.barcode || l.sku_code || l.sku_code_snapshot || "-";

              return `
            <tr>
              <td>${this.escapeHtml(l.sku_code || l.sku_code_snapshot || "-")}</td>
              <td>${this.escapeHtml(lineIdentifier)}</td>
              <td class="th-center">${this.escapeHtml(String(l.qty_returned ?? "-"))}</td>
              <td class="th-center">${this.escapeHtml(String(l.scanned_qty ?? "-"))}</td>
              <td class="th-center">${this.escapeHtml(String(l.pending_scan_qty ?? "-"))}</td>
              <td class="th-center">${this.escapeHtml(lineStatus)}</td>
            </tr>
          `;
            })
            .join("")
        : `
        <tr>
          <td colspan="6" class="table-empty">No return lines</td>
        </tr>
      `;

    host.innerHTML = `
      <section class="panel returns-inline-detail">
        <div class="panel__header">
          <div>
            <h2>Return Detail</h2>
            <p>${this.escapeHtml(this.shipmentHintFor(shipment))}</p>
          </div>

          <button
            type="button"
            class="btn btn-secondary"
            data-action="click->returns#toggleDetail"
            data-id="${shipment.id}">
            Close
          </button>
        </div>

        <div class="market-meta-grid">
          <div class="market-meta">
            <div class="market-meta__label">Return ID</div>
            <div class="market-meta__value">${this.escapeHtml(shipment.external_return_id || "-")}</div>
          </div>

          <div class="market-meta">
            <div class="market-meta__label">Order ID</div>
            <div class="market-meta__value">${this.escapeHtml(shipment.external_order_id || "-")}</div>
          </div>

          <div class="market-meta">
            <div class="market-meta__label">Buyer</div>
            <div class="market-meta__value">${this.escapeHtml(shipment.buyer_username || "-")}</div>
          </div>

          <div class="market-meta">
            <div class="market-meta__label">Store Status</div>
            <div class="market-meta__value">${this.escapeHtml(this.humanizeStoreStatus(shipment.derived_status_store || shipment.status_store))}</div>
          </div>

          <div class="market-meta">
            <div class="market-meta__label">Marketplace Status</div>
            <div class="market-meta__value">${this.escapeHtml(this.humanizeMarketplaceStatus(shipment.status_marketplace))}</div>
          </div>

          <div class="market-meta">
            <div class="market-meta__label">Carrier</div>
            <div class="market-meta__value">${this.escapeHtml(shipment.return_carrier_method || "-")}</div>
          </div>

          <div class="market-meta">
            <div class="market-meta__label">Tracking</div>
            <div class="market-meta__value">${this.escapeHtml(this.trackingTextFor(shipment))}</div>
          </div>

          <div class="market-meta market-meta--wide">
            <div class="market-meta__label">Shipment Status</div>
            <div class="market-meta__value">${this.escapeHtml(this.shipmentHintFor(shipment))}</div>
          </div>
        </div>

        <div class="pos-summary" style="margin-top: 16px;">
          <strong>Scanned ${this.escapeHtml(String(shipment.total_qty_scanned))} / ${this.escapeHtml(String(shipment.total_qty_requested))}</strong>
        </div>

        <div class="pos-field" style="margin-top: 16px;">
          <label>Scan Barcode / SKU Code</label>
          <input
            type="text"
            placeholder="${fullyScanned ? "Return นี้รับครบแล้ว" : "ยิง Barcode หรือพิมพ์ SKU Code แล้วกด Enter"}"
            data-inline-scan-input-id="${shipment.id}"
            data-action="keydown->returns#onInlineScanKeydown"
            ${fullyScanned ? "disabled" : ""}>
          <p class="pos-field__hint">${this.escapeHtml(scanHint)}</p>
        </div>

        <div class="table-wrap" style="margin-top: 16px;">
          <table class="pos-table">
            <thead>
              <tr>
                <th>SKU</th>
                <th>Barcode / Scan Input</th>
                <th class="th-center">Requested</th>
                <th class="th-center">Scanned</th>
                <th class="th-center">Pending</th>
                <th class="th-center">Status</th>
              </tr>
            </thead>

            <tbody>
              ${lineRows}
            </tbody>
          </table>
        </div>
      </section>
    `;

    if (!fullyScanned) {
      const input = this.findInlineScanInput(shipment.id);
      if (input) {
        setTimeout(() => input.focus(), 50);
      }
    }
  }

  async onInlineScanKeydown(e) {
    if (e.key !== "Enter") return;
    if (this.scanLoading) return;

    e.preventDefault();

    if (!this.currentShipment) {
      this.toast("Select shipment first");
      return;
    }

    const input = e.currentTarget;
    if (input.disabled) {
      this.toast("This return is already fully scanned");
      return;
    }

    const scanInput = input.value.trim();
    if (!scanInput) return;

    this.scanLoading = true;

    try {
      const data = await this.request("/pos/returns/scan", {
        method: "POST",
        body: JSON.stringify({
          return_shipment_id: this.currentShipment.id,
          barcode: scanInput,
          quantity: 1,
          idempotency_key: this.generateKey("returns:scan"),
        }),
      });

      if (!data) return;

      const matchType =
        data.scan_match_type === "sku_code" ? "SKU Code" : "Barcode";
      this.toast(`Scanned by ${matchType}`);
      input.value = "";

      await this.loadExpandedDetail(this.currentShipment.id);
      this.fetchList();
    } catch (e2) {
      this.toast(this.humanizeScanError(e2.message));
    } finally {
      this.scanLoading = false;
    }
  }

  findDetailHost(id) {
    return this.element.querySelector(
      `[data-detail-host-id="${CSS.escape(String(id))}"]`,
    );
  }

  findInlineScanInput(id) {
    return this.element.querySelector(
      `[data-inline-scan-input-id="${CSS.escape(String(id))}"]`,
    );
  }

  humanizeScanError(message) {
    const raw = (message || "").toString();

    if (raw.includes("sku not found for scan input")) {
      return "ไม่พบ SKU จาก Barcode หรือ SKU Code นี้";
    }

    if (raw.includes("return shipment line not found for scan input")) {
      return "SKU นี้ไม่อยู่ในรายการ return ที่เลือกไว้ หรือรับครบแล้ว";
    }

    if (raw.includes("order_line not mapped")) {
      return "รายการนี้ยัง map order line ไม่ได้ จึงยังสแกนไม่ได้";
    }

    if (raw.includes("SKU mismatch")) {
      return "SKU ไม่ตรงกับรายการ return นี้";
    }

    if (
      raw.toLowerCase().includes("unauthorized") ||
      raw === "not authorized"
    ) {
      return "POS key ไม่ถูกต้องหรือไม่ได้ส่งมาพร้อมคำขอ";
    }

    return raw;
  }

  trackingTextFor(shipment) {
    if (shipment?.tracking_number) return shipment.tracking_number;
    if (shipment?.return_carrier_method) return "Waiting for buyer to ship";
    return "No tracking";
  }

  shipmentHintFor(shipment) {
    const storeStatus =
      shipment?.derived_status_store || shipment?.status_store;
    const marketplaceStatus = (shipment?.status_marketplace || "")
      .toString()
      .toLowerCase();

    if (storeStatus === "received_scanned") return "Received at store";
    if (storeStatus === "partial_scanned") return "Partially received at store";
    if (shipment?.tracking_number) return "In transit / shipped back";
    if (shipment?.return_carrier_method) return "Waiting for buyer to ship";
    if (marketplaceStatus === "completed") return "Completed in marketplace";
    return "Return requested";
  }

  scanHintFor(shipment) {
    const storeStatus =
      shipment?.derived_status_store || shipment?.status_store;

    if (storeStatus === "partial_scanned") {
      return "มีบางชิ้นรับเข้าแล้ว สแกนต่อได้จนกว่าจะครบ";
    }

    if (shipment?.tracking_number) {
      return "สแกนได้ทั้ง Barcode และ SKU Code เมื่อของมาถึงร้าน";
    }

    if (shipment?.return_carrier_method) {
      return "ถ้าไม่มี Barcode สามารถพิมพ์ SKU Code แล้วกด Enter ได้";
    }

    return "สแกนได้ทั้ง Barcode และ SKU Code";
  }

  humanizeStoreStatus(status) {
    switch ((status || "").toString()) {
      case "pending_scan":
        return "Pending";
      case "partial_scanned":
        return "Partial";
      case "received_scanned":
        return "Received";
      default:
        return status || "-";
    }
  }

  humanizeMarketplaceStatus(status) {
    switch ((status || "").toString()) {
      case "requested":
        return "Requested";
      case "shipped_back":
        return "In transit / shipped back";
      case "completed":
        return "Completed";
      default:
        return status || "-";
    }
  }

  statusClassFor(status) {
    switch ((status || "").toString()) {
      case "pending_scan":
        return "pending_scan";
      case "partial_scanned":
        return "partial_scanned";
      case "received_scanned":
        return "received_scanned";
      default:
        return "";
    }
  }

  isReceivedScanned(shipment) {
    const status = shipment?.derived_status_store || shipment?.status_store;
    return status === "received_scanned";
  }

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  formatDateTime(value) {
    if (!value) return "-";
    const d = new Date(value);
    return d.toLocaleString("th-TH");
  }
}
