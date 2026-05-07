export const productManagementImportMethods = {
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
  },

  closeImportModal(event) {
    if (event && event.target === this.importModalTarget) return;

    this.importModalBackdropTarget.classList.add("hidden");
    this.importModalTarget.classList.add("hidden");
  },

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
  },

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
    this.importSubmitButtonTarget.textContent = "Uploading...";
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

      if (!data.batch_id) {
        throw new Error("Upload queued but batch_id was missing");
      }

      this.showImportMessage(
        "success",
        `Upload queued. Processing batch #${data.batch_id}...`,
      );

      this.importSubmitButtonTarget.textContent = "Processing...";

      const batch = await this.pollImportBatchStatus(data.batch_id);
      this.renderImportBatchResult(batch);

      if (batch.status === "completed") {
        this.showImportMessage("success", "Import completed");
        await this.loadSkus();
        await this.loadFacets();
      } else {
        throw new Error(batch.error_message || "Import failed");
      }
    } catch (error) {
      console.error("submitImport error", error);
      this.showImportMessage("error", error.message);
    } finally {
      this.importSubmitButtonTarget.disabled = false;
      this.importSubmitButtonTarget.textContent = "Upload CSV";
    }
  },

  async pollImportBatchStatus(batchId) {
    const maxAttempts = 120;
    const delayMs = 2000;

    for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
      const response = await fetch(`/ops/sku_imports/${batchId}`, {
        headers: this.jsonHeaders(),
      });

      const data = await this.parseJsonResponse(
        response,
        `pollImportBatchStatus /ops/sku_imports/${batchId}`,
      );

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Failed to check import status");
      }

      const batch = data.batch;

      this.showImportMessage(
        "success",
        `Import ${batch.status}: ${batch.upsert_rows || 0}/${batch.total_rows || 0} rows`,
      );

      this.renderImportBatchResult(batch);

      if (batch.status === "completed" || batch.status === "failed") {
        return batch;
      }

      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }

    throw new Error("Import is still processing. Please check again later.");
  },

  renderImportBatchResult(batch) {
    this.renderImportResult({
      total_rows: batch.total_rows,
      upsert_rows: batch.upsert_rows,
      duplicate_rows_in_file: 0,
      invalid_format_rows: 0,
      stock_updated: batch.stock_updated,
      stock_failed: batch.stock_failed,
      stock_failed_samples: batch.result?.stock_failed_samples || [],
      dry_run: batch.dry_run,
    });
  },

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
            <div class="import-result-mini__value ${label.includes("Failed") ? "text-danger" : ""}">
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
  },

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
  },

  hideImportMessage() {
    this.importMessageTarget.textContent = "";
    this.importMessageTarget.classList.add("hidden");
    this.importMessageTarget.classList.remove("is-error", "is-success");
  },

  hideImportResult() {
    this.importResultTarget.innerHTML = "";
    this.importResultTarget.classList.add("hidden");
  },
};
