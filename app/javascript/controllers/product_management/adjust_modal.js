export const productManagementAdjustMethods = {
  closeAdjustModal(event) {
    if (event && event.target === this.adjustModalTarget) return;
    this.modalBackdropTarget.classList.add("hidden");
    this.adjustModalTarget.classList.add("hidden");
  },

  onAdjustModeChange() {
    const mode = this.adjustModeTarget.value;

    this.quantityFieldTarget.classList.toggle("hidden", mode !== "stock_in");
    this.deltaFieldTarget.classList.toggle("hidden", mode !== "adjust_delta");
    this.setToFieldTarget.classList.toggle("hidden", mode !== "adjust_set");
    this.bufferFieldTarget.classList.remove("hidden");
  },

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
  },

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
  },

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
  },

  hideAdjustMessage() {
    this.adjustMessageTarget.textContent = "";
    this.adjustMessageTarget.classList.add("hidden");
    this.adjustMessageTarget.classList.remove("is-error", "is-success");
  },

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
  },
};
