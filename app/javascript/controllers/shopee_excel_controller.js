import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "importFileInput",
    "importFilePicker",
    "importFileName",
    "importButton",
    "importMessage",
    "importSummary",
    "importTotalRows",
    "importSuccessRows",
    "importFailedRows",
    "importErrorSummary",

    "returnFileInput",
    "returnFilePicker",
    "returnFileName",
    "returnButton",
    "returnMessage",
    "returnSummary",
    "returnTotalRows",
    "returnSuccessRows",
    "returnFailedRows",
    "returnErrorSummary",

    "exportFileInput",
    "exportFilePicker",
    "exportFileName",
    "exportButton",
    "exportMessage",
  ];

  static values = {
    shopId: Number,
  };

  importFileChanged() {
    this.updateSelectedFileUI(
      this.importFileInputTarget,
      this.importFileNameTarget,
      this.importFilePickerTarget,
    );
    this.resetImportState();
  }

  returnFileChanged() {
    this.updateSelectedFileUI(
      this.returnFileInputTarget,
      this.returnFileNameTarget,
      this.returnFilePickerTarget,
    );
    this.hideReturnSummary();
    this.hideMessage(this.returnMessageTarget);
  }

  exportFileChanged() {
    this.updateSelectedFileUI(
      this.exportFileInputTarget,
      this.exportFileNameTarget,
      this.exportFilePickerTarget,
    );
    this.hideMessage(this.exportMessageTarget);
  }

  async uploadOrders() {
    const file = this.importFileInputTarget.files[0];

    if (!file) {
      this.hideImportSummary();
      this.showMessage(
        this.importMessageTarget,
        "Please choose a .xlsx file",
        "error",
      );
      return;
    }

    if (!this.isXlsxFile(file)) {
      this.hideImportSummary();
      this.showMessage(
        this.importMessageTarget,
        "Only .xlsx files are supported",
        "error",
      );
      return;
    }

    this.hideMessage(this.importMessageTarget);
    this.hideImportSummary();
    this.setButtonLoading(this.importButtonTarget, true, "Uploading...");

    try {
      const formData = new FormData();
      formData.append("file", file);

      if (this.hasShopIdValue && this.shopIdValue) {
        formData.append("shop_id", this.shopIdValue);
      }

      const response = await fetch("/shopee/orders/import", {
        method: "POST",
        headers: {
          "X-CSRF-Token": this.csrfToken(),
          Accept: "application/json",
        },
        body: formData,
      });

      const data = await this.parseJsonResponse(
        response,
        "uploadOrders /shopee/orders/import",
      );

      if (!response.ok || !data.ok) {
        throw new Error(data.message || data.error || "Import failed");
      }

      this.importTotalRowsTarget.textContent = data.total_rows ?? 0;
      this.importSuccessRowsTarget.textContent = data.success_rows ?? 0;
      this.importFailedRowsTarget.textContent = data.failed_rows ?? 0;
      this.importSummaryTarget.classList.remove("is-hidden");

      if (data.error_summary) {
        this.importErrorSummaryTarget.textContent = data.error_summary;
        this.importErrorSummaryTarget.classList.remove("is-hidden");
      } else {
        this.importErrorSummaryTarget.textContent = "";
        this.importErrorSummaryTarget.classList.add("is-hidden");
      }

      const completedWithErrors = data.batch_status === "completed_with_errors";
      this.showMessage(
        this.importMessageTarget,
        completedWithErrors
          ? "Upload completed with errors"
          : "Upload completed",
        completedWithErrors ? "error" : "success",
      );
    } catch (error) {
      this.hideImportSummary();
      this.showMessage(
        this.importMessageTarget,
        error.message || "Import failed",
        "error",
      );
    } finally {
      this.setButtonLoading(this.importButtonTarget, false, "Upload");
    }
  }

  async uploadReturns() {
    const file = this.returnFileInputTarget.files[0];

    if (!file) {
      this.hideReturnSummary();
      this.showMessage(
        this.returnMessageTarget,
        "Please choose a .xlsx file",
        "error",
      );
      return;
    }

    if (!this.isXlsxFile(file)) {
      this.hideReturnSummary();
      this.showMessage(
        this.returnMessageTarget,
        "Only .xlsx files are supported",
        "error",
      );
      return;
    }

    this.hideMessage(this.returnMessageTarget);
    this.hideReturnSummary();
    this.setButtonLoading(this.returnButtonTarget, true, "Uploading...");

    try {
      const formData = new FormData();
      formData.append("file", file);

      if (this.hasShopIdValue && this.shopIdValue) {
        formData.append("shop_id", this.shopIdValue);
      }

      const response = await fetch("/shopee/returns/import", {
        method: "POST",
        headers: {
          "X-CSRF-Token": this.csrfToken(),
          Accept: "application/json",
        },
        body: formData,
      });

      const data = await this.parseJsonResponse(
        response,
        "uploadReturns /shopee/returns/import",
      );

      if (!response.ok || !data.ok) {
        throw new Error(data.message || data.error || "Import failed");
      }

      this.returnTotalRowsTarget.textContent = data.total_rows ?? 0;
      this.returnSuccessRowsTarget.textContent = data.success_rows ?? 0;
      this.returnFailedRowsTarget.textContent = data.failed_rows ?? 0;
      this.returnSummaryTarget.classList.remove("is-hidden");

      if (data.error_summary) {
        this.returnErrorSummaryTarget.textContent = data.error_summary;
        this.returnErrorSummaryTarget.classList.remove("is-hidden");
      } else {
        this.returnErrorSummaryTarget.textContent = "";
        this.returnErrorSummaryTarget.classList.add("is-hidden");
      }

      const completedWithErrors = data.batch_status === "completed_with_errors";

      this.showMessage(
        this.returnMessageTarget,
        completedWithErrors
          ? "Upload completed with errors"
          : "Upload completed",
        completedWithErrors ? "error" : "success",
      );
    } catch (error) {
      this.hideReturnSummary();
      this.showMessage(
        this.returnMessageTarget,
        error.message || "Import failed",
        "error",
      );
    } finally {
      this.setButtonLoading(this.returnButtonTarget, false, "Upload Returns");
    }
  }

  async exportStock() {
    const file = this.exportFileInputTarget.files[0];

    if (!file) {
      this.showMessage(
        this.exportMessageTarget,
        "Please choose a .xlsx template",
        "error",
      );
      return;
    }

    if (!this.isXlsxFile(file)) {
      this.showMessage(
        this.exportMessageTarget,
        "Only .xlsx files are supported",
        "error",
      );
      return;
    }

    this.hideMessage(this.exportMessageTarget);
    this.setButtonLoading(this.exportButtonTarget, true, "Exporting...");

    try {
      const formData = new FormData();
      formData.append("file", file);

      if (this.hasShopIdValue && this.shopIdValue) {
        formData.append("shop_id", this.shopIdValue);
      }

      const response = await fetch("/shopee/stocks/export", {
        method: "POST",
        headers: {
          "X-CSRF-Token": this.csrfToken(),
          Accept:
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        },
        body: formData,
      });

      const contentType = response.headers.get("content-type") || "";

      if (!response.ok) {
        if (contentType.includes("application/json")) {
          const data = await this.parseJsonResponse(
            response,
            "exportStock /shopee/stocks/export error",
          );
          throw new Error(data.message || data.error || "Export failed");
        }

        throw new Error("Export failed");
      }

      if (
        !contentType.includes(
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )
      ) {
        if (contentType.includes("application/json")) {
          const data = await this.parseJsonResponse(
            response,
            "exportStock /shopee/stocks/export unexpected content type",
          );
          throw new Error(data.message || data.error || "Export failed");
        }

        throw new Error("Download failed: server did not return an Excel file");
      }

      const blob = await response.blob();

      if (!blob || blob.size === 0) {
        throw new Error("Download failed: empty file");
      }

      const disposition = response.headers.get("content-disposition") || "";
      const filename =
        this.extractFilename(disposition) || "shopee_stock_export.xlsx";

      this.downloadBlob(blob, filename);
      this.showMessage(this.exportMessageTarget, "Export completed", "success");
    } catch (error) {
      this.showMessage(
        this.exportMessageTarget,
        error.message || "Export failed",
        "error",
      );
    } finally {
      this.setButtonLoading(
        this.exportButtonTarget,
        false,
        "Export Current Stock",
      );
    }
  }

  resetImportState() {
    this.hideMessage(this.importMessageTarget);
    this.hideImportSummary();
  }

  hideImportSummary() {
    this.importSummaryTarget.classList.add("is-hidden");
    this.importErrorSummaryTarget.classList.add("is-hidden");
    this.importErrorSummaryTarget.textContent = "";
  }

  hideReturnSummary() {
    this.returnSummaryTarget.classList.add("is-hidden");
    this.returnErrorSummaryTarget.classList.add("is-hidden");
    this.returnErrorSummaryTarget.textContent = "";
  }

  updateSelectedFileUI(input, nameTarget, pickerTarget) {
    const file = input.files[0];

    if (file) {
      nameTarget.textContent = file.name;
      pickerTarget.classList.add("is-selected");
    } else {
      nameTarget.textContent = "No file selected";
      pickerTarget.classList.remove("is-selected");
    }
  }

  isXlsxFile(file) {
    const name = file.name.toLowerCase();
    return name.endsWith(".xlsx") || name.endsWith(".xls");
  }

  hideMessage(target) {
    target.textContent = "";
    target.classList.add("is-hidden");
    target.classList.remove("is-success", "is-error");
  }

  showMessage(target, message, type) {
    target.textContent = message;
    target.classList.remove("is-hidden", "is-success", "is-error");
    target.classList.add(type === "success" ? "is-success" : "is-error");
  }

  setButtonLoading(button, isLoading, loadingText) {
    if (!button.dataset.originalText) {
      button.dataset.originalText = button.textContent;
    }

    button.disabled = isLoading;
    button.textContent = isLoading ? loadingText : button.dataset.originalText;
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || "";
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

  extractFilename(disposition) {
    const utf8Match = disposition.match(/filename\*=UTF-8''([^;]+)/i);
    if (utf8Match) return decodeURIComponent(utf8Match[1]);

    const plainMatch = disposition.match(/filename="([^"]+)"/i);
    if (plainMatch) return plainMatch[1];

    return null;
  }

  downloadBlob(blob, filename) {
    const blobUrl = window.URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = blobUrl;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.URL.revokeObjectURL(blobUrl);
  }
}
