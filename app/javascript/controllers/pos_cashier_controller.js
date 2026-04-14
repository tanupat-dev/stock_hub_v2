import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "scanInput",
    "cartBody",
    "saleHeadline",
    "saleMeta",
    "leftHint",
    "itemCount",
    "checkoutButton",
    "voidButton",
    "searchModal",
    "searchInput",
    "searchResults",
    "cartEmptyState",
    "cartContent",
    "cartSubhead",
    "workflowBlock",
    "afterCheckoutBlock",
    "startSaleBlock",
    "startSaleButton",
    "searchButton",
    "newSaleAgainButton",
    "saleStatusCard",
  ];

  connect() {
    this.loading = false;
    this.searchTimeout = null;
    this.currentSale = null;
    this.render();
  }

  posKey() {
    return document.querySelector('meta[name="pos-key"]')?.content || "";
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || "";
  }

  generateKey(prefix) {
    return `${prefix}:${Date.now()}:${Math.random().toString(16).slice(2, 8)}`;
  }

  async request(url, options = {}) {
    if (this.loading) return null;

    this.loading = true;

    try {
      const response = await fetch(url, {
        method: options.method || "GET",
        headers: {
          "Content-Type": "application/json",
          "X-POS-KEY": this.posKey(),
          "X-CSRF-Token": this.csrfToken(),
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
    } finally {
      this.loading = false;
      this.updateActionAvailability();
    }
  }

  toast(message) {
    const el = document.createElement("div");
    el.className = "pos-toast";
    el.textContent = message;

    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2200);
  }

  focusScan() {
    setTimeout(() => {
      if (this.hasScanInputTarget && !this.scanInputTarget.disabled) {
        this.scanInputTarget.focus();
        this.scanInputTarget.select?.();
      }
    }, 50);
  }

  focusSearch() {
    setTimeout(() => {
      if (this.hasSearchInputTarget) {
        this.searchInputTarget.focus();
        this.searchInputTarget.select?.();
      }
    }, 50);
  }

  flashScanSuccess() {
    if (!this.hasScanInputTarget) return;

    this.scanInputTarget.classList.add("pos-scan-success");

    setTimeout(() => {
      this.scanInputTarget.classList.remove("pos-scan-success");
    }, 250);
  }

  isCartSale() {
    return this.currentSale?.status === "cart";
  }

  isCheckedOutSale() {
    return this.currentSale?.status === "checked_out";
  }

  isVoidedSale() {
    return this.currentSale?.status === "voided";
  }

  hasItems() {
    return Number(this.currentSale?.item_count || 0) > 0;
  }

  setSale(sale) {
    this.currentSale = sale;
    this.render();
  }

  async createSale() {
    try {
      const data = await this.request("/pos/sales", {
        method: "POST",
        body: JSON.stringify({
          idempotency_key: this.generateKey("pos:create_sale"),
        }),
      });

      if (!data) return;

      this.setSale(data.sale);
      this.toast("New sale started");
    } catch (e) {
      this.toast(e.message);
    }
  }

  async onScanKeydown(e) {
    if (e.key !== "Enter") return;

    e.preventDefault();

    if (!this.currentSale) {
      this.toast("Start New Sale first");
      return;
    }

    if (!this.isCartSale()) {
      this.toast("This sale is locked");
      return;
    }

    const barcode = this.scanInputTarget.value.trim();
    if (!barcode) return;

    try {
      const data = await this.request(
        `/pos/sales/${this.currentSale.id}/add_line`,
        {
          method: "POST",
          body: JSON.stringify({
            barcode,
            quantity: 1,
            idempotency_key: this.generateKey("pos:add_line"),
          }),
        },
      );

      if (!data) return;

      this.setSale(data.sale);
      this.scanInputTarget.value = "";
      this.flashScanSuccess();
      this.focusScan();
    } catch (e) {
      this.toast(e.message);

      if (e.message.toLowerCase().includes("not found")) {
        this.openSearch();
        this.searchInputTarget.value = barcode;
        this.search();
      }
    }
  }

  async updateQty(lineId, quantity) {
    if (!this.currentSale || !this.isCartSale()) return;

    try {
      const data = await this.request(
        `/pos/sales/${this.currentSale.id}/update_line`,
        {
          method: "PATCH",
          body: JSON.stringify({
            line_id: lineId,
            quantity,
            idempotency_key: this.generateKey("pos:update_line"),
          }),
        },
      );

      if (!data) return;

      this.setSale(data.sale);
      this.focusScan();
    } catch (e) {
      this.toast(e.message);
    }
  }

  async removeLine(lineId) {
    if (!this.currentSale || !this.isCartSale()) return;

    try {
      const data = await this.request(
        `/pos/sales/${this.currentSale.id}/remove_line`,
        {
          method: "DELETE",
          body: JSON.stringify({
            line_id: lineId,
            idempotency_key: this.generateKey("pos:remove_line"),
          }),
        },
      );

      if (!data) return;

      this.setSale(data.sale);
      this.focusScan();
    } catch (e) {
      this.toast(e.message);
    }
  }

  async checkout() {
    if (!this.currentSale) {
      this.toast("Start New Sale first");
      return;
    }

    if (!this.isCartSale()) {
      this.toast("This sale cannot be checked out");
      return;
    }

    if (!this.hasItems()) {
      this.toast("No items in cart");
      return;
    }

    try {
      const data = await this.request(
        `/pos/sales/${this.currentSale.id}/checkout`,
        {
          method: "POST",
          body: JSON.stringify({
            idempotency_key: this.generateKey("pos:checkout"),
          }),
        },
      );

      if (!data) return;

      this.setSale(data.sale);
      this.toast("Checkout success");
    } catch (e) {
      this.toast(e.message);
    }
  }

  async voidSale() {
    if (!this.currentSale) return;

    if (!this.isCheckedOutSale()) {
      this.toast("Only checked out sale can be voided");
      return;
    }

    try {
      const data = await this.request(
        `/pos/sales/${this.currentSale.id}/void`,
        {
          method: "POST",
          body: JSON.stringify({
            idempotency_key: this.generateKey("pos:void"),
          }),
        },
      );

      if (!data) return;

      this.setSale(data.sale);
      this.toast("Sale voided");
    } catch (e) {
      this.toast(e.message);
    }
  }

  openSearch() {
    if (!this.currentSale || !this.isCartSale()) {
      this.toast("Start New Sale first");
      return;
    }

    this.searchModalTarget.classList.remove("hidden");
    this.focusSearch();
  }

  closeSearch() {
    this.searchModalTarget.classList.add("hidden");
    this.focusScan();
  }

  onSearchInput() {
    clearTimeout(this.searchTimeout);

    this.searchTimeout = setTimeout(() => {
      this.search();
    }, 250);
  }

  async search() {
    const q = this.searchInputTarget.value.trim();

    if (!q) {
      this.searchResultsTarget.innerHTML = `<div class="table-empty">Type to search</div>`;
      return;
    }

    try {
      const data = await this.request(
        `/pos/skus/search?q=${encodeURIComponent(q)}&limit=20`,
      );

      if (!data) return;

      this.renderSearchResults(data.skus || []);
    } catch (e) {
      this.toast(e.message);
    }
  }

  renderSearchResults(skus) {
    if (!skus.length) {
      this.searchResultsTarget.innerHTML = `<div class="table-empty">No result</div>`;
      return;
    }

    this.searchResultsTarget.innerHTML = skus
      .map((sku) => {
        const subtitle = [sku.brand, sku.model, sku.color, sku.size]
          .filter(Boolean)
          .join(" / ");

        return `
        <button
          type="button"
          class="pos-search-item"
          data-barcode="${sku.barcode || ""}"
          data-action="click->pos-cashier#selectSku">
          <div class="pos-search-item__title">${sku.code}</div>
          <div class="pos-search-item__meta">${subtitle || "-"}</div>
          <div class="pos-search-item__meta">Barcode: ${sku.barcode || "-"}</div>
        </button>
      `;
      })
      .join("");
  }

  async selectSku(e) {
    const barcode = e.currentTarget.dataset.barcode;

    if (!barcode) {
      this.toast("Selected SKU has no barcode");
      return;
    }

    this.closeSearch();
    this.scanInputTarget.value = barcode;

    await this.onScanKeydown({
      key: "Enter",
      preventDefault() {},
    });
  }

  increase(e) {
    const lineId = e.currentTarget.dataset.lineId;
    const line = (this.currentSale?.lines || []).find(
      (row) => String(row.id) === String(lineId),
    );
    if (!line) return;

    this.updateQty(lineId, Number(line.quantity) + 1);
  }

  decrease(e) {
    const lineId = e.currentTarget.dataset.lineId;
    const line = (this.currentSale?.lines || []).find(
      (row) => String(row.id) === String(lineId),
    );
    if (!line) return;

    const nextQty = Number(line.quantity) - 1;

    if (nextQty <= 0) {
      this.removeLine(lineId);
      return;
    }

    this.updateQty(lineId, nextQty);
  }

  remove(e) {
    const lineId = e.currentTarget.dataset.lineId;
    this.removeLine(lineId);
  }

  render() {
    if (!this.currentSale) {
      this.renderNoSaleState();
      return;
    }

    if (this.isVoidedSale()) {
      this.renderVoidedState();
      return;
    }

    if (this.isCheckedOutSale()) {
      this.renderCheckedOutState();
      return;
    }

    this.renderCartState();
  }

  renderNoSaleState() {
    this.saleHeadlineTarget.textContent = "No active sale";
    this.saleMetaTarget.textContent = "ยังไม่มีบิลที่กำลังขายอยู่";
    this.leftHintTarget.textContent = "เริ่มต้นโดยกด Start New Sale";

    this.startSaleBlockTarget.classList.remove("hidden");
    this.workflowBlockTarget.classList.add("hidden");
    this.afterCheckoutBlockTarget.classList.add("hidden");

    this.cartEmptyStateTarget.classList.remove("hidden");
    this.cartContentTarget.classList.add("hidden");

    this.cartSubheadTarget.textContent = "ยังไม่มีบิลที่กำลังขาย";
    this.itemCountTarget.textContent = "0";
    this.cartBodyTarget.innerHTML = `
      <tr>
        <td colspan="4" class="table-empty">No items yet</td>
      </tr>
    `;

    this.updateActionAvailability();
  }

  renderCartState() {
    this.saleHeadlineTarget.textContent = "Current Bill";
    this.saleMetaTarget.textContent = "Ready to scan items";
    this.leftHintTarget.textContent = "Step 2: Scan barcode หรือใช้ Search SKU";

    this.startSaleBlockTarget.classList.add("hidden");
    this.workflowBlockTarget.classList.remove("hidden");
    this.afterCheckoutBlockTarget.classList.add("hidden");

    this.cartEmptyStateTarget.classList.add("hidden");
    this.cartContentTarget.classList.remove("hidden");

    this.cartSubheadTarget.textContent = "Step 3: ตรวจสินค้า แล้วกด Checkout";
    this.itemCountTarget.textContent = String(this.currentSale.item_count || 0);

    this.renderCartRows();
    this.updateActionAvailability();
    this.focusScan();
  }

  renderCheckedOutState() {
    this.saleHeadlineTarget.textContent = "Sale Completed";
    this.saleMetaTarget.textContent = "Payment completed";
    this.leftHintTarget.textContent = "บิลนี้ขายเสร็จแล้ว";

    this.startSaleBlockTarget.classList.add("hidden");
    this.workflowBlockTarget.classList.add("hidden");
    this.afterCheckoutBlockTarget.classList.remove("hidden");

    this.cartEmptyStateTarget.classList.add("hidden");
    this.cartContentTarget.classList.remove("hidden");

    this.cartSubheadTarget.textContent = "บิลนี้ถูก checkout แล้ว";
    this.itemCountTarget.textContent = String(this.currentSale.item_count || 0);

    this.renderCartRows({ locked: true });
    this.updateActionAvailability();
  }

  renderVoidedState() {
    this.saleHeadlineTarget.textContent = "Sale Voided";
    this.saleMetaTarget.textContent = "This sale was cancelled";
    this.leftHintTarget.textContent =
      "บิลนี้ถูก void แล้ว เริ่มบิลใหม่ได้ทันที";

    this.startSaleBlockTarget.classList.remove("hidden");
    this.workflowBlockTarget.classList.add("hidden");
    this.afterCheckoutBlockTarget.classList.add("hidden");

    this.cartEmptyStateTarget.classList.remove("hidden");
    this.cartContentTarget.classList.add("hidden");

    this.cartSubheadTarget.textContent = "บิลล่าสุดถูก void แล้ว";
    this.itemCountTarget.textContent = "0";
    this.cartBodyTarget.innerHTML = `
    <tr>
      <td colspan="4" class="table-empty">This sale was voided</td>
    </tr>
  `;

    this.updateActionAvailability();
  }

  renderCartRows({ locked = false } = {}) {
    const lines = this.currentSale?.lines || [];

    if (!lines.length) {
      this.cartBodyTarget.innerHTML = `
        <tr>
          <td colspan="4" class="table-empty">No items yet. Scan barcode to add item.</td>
        </tr>
      `;
      return;
    }

    this.cartBodyTarget.innerHTML = lines
      .map((line) => {
        const qtyCell = locked
          ? `<span>${line.quantity}</span>`
          : `
          <div class="qty-control">
            <button
              type="button"
              class="qty-btn"
              data-line-id="${line.id}"
              data-action="click->pos-cashier#decrease">-</button>
            <span>${line.quantity}</span>
            <button
              type="button"
              class="qty-btn"
              data-line-id="${line.id}"
              data-action="click->pos-cashier#increase">+</button>
          </div>
        `;

        const actionCell = locked
          ? `<span class="pos-muted">Locked</span>`
          : `
          <button
            type="button"
            class="remove-btn"
            data-line-id="${line.id}"
            data-action="click->pos-cashier#remove">
            Remove
          </button>
        `;

        return `
        <tr>
          <td><strong>${line.sku_code || "-"}</strong></td>
          <td>${line.barcode || "-"}</td>
          <td class="th-center">${qtyCell}</td>
          <td>${actionCell}</td>
        </tr>
      `;
      })
      .join("");
  }

  updateActionAvailability() {
    const hasSale = !!this.currentSale;
    const isCart = this.isCartSale();
    const isCheckedOut = this.isCheckedOutSale();
    const hasItems = this.hasItems();
    const isBusy = this.loading;

    if (this.hasStartSaleButtonTarget) {
      this.startSaleButtonTarget.disabled = isBusy;
    }

    if (this.hasNewSaleAgainButtonTarget) {
      this.newSaleAgainButtonTarget.disabled = isBusy;
    }

    if (this.hasSearchButtonTarget) {
      this.searchButtonTarget.disabled = !hasSale || !isCart || isBusy;
    }

    if (this.hasCheckoutButtonTarget) {
      this.checkoutButtonTarget.disabled =
        !hasSale || !isCart || !hasItems || isBusy;
    }

    if (this.hasVoidButtonTarget) {
      this.voidButtonTarget.disabled = !hasSale || !isCheckedOut || isBusy;
    }

    if (this.hasScanInputTarget) {
      this.scanInputTarget.disabled = !hasSale || !isCart || isBusy;
    }
  }
}
