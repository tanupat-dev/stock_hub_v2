// app/javascript/controllers/marketplace_connections_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "tiktokShopName",
    "tiktokShopId",
    "tiktokAppKey",
    "tiktokAppSecret",
    "tiktokSubmitButton",
    "tiktokError",
    "lazadaShopName",
    "lazadaSellerId",
    "lazadaAppKey",
    "lazadaAppSecret",
    "lazadaSubmitButton",
    "lazadaError",
    "tiktokCallbackValue",
    "lazadaCallbackValue",
    "tiktokCopyButton",
    "lazadaCopyButton",
  ];

  connect() {
    this.resetForms();
  }

  async submitTiktok(event) {
    event.preventDefault();

    const payload = {
      channel: "tiktok",
      shop_name: this.tiktokShopNameTarget.value,
      shop_id: this.tiktokShopIdTarget.value,
      app_key: this.tiktokAppKeyTarget.value,
      app_secret: this.tiktokAppSecretTarget.value,
    };

    await this.submitConnection({
      payload,
      button: this.tiktokSubmitButtonTarget,
      errorBox: this.tiktokErrorTarget,
      loadingText: "Connecting TikTok...",
    });
  }

  async submitLazada(event) {
    event.preventDefault();

    const payload = {
      channel: "lazada",
      shop_name: this.lazadaShopNameTarget.value,
      seller_id: this.lazadaSellerIdTarget.value,
      app_key: this.lazadaAppKeyTarget.value,
      app_secret: this.lazadaAppSecretTarget.value,
    };

    await this.submitConnection({
      payload,
      button: this.lazadaSubmitButtonTarget,
      errorBox: this.lazadaErrorTarget,
      loadingText: "Connecting Lazada...",
    });
  }

  async submitConnection({ payload, button, errorBox, loadingText }) {
    this.clearError(errorBox);

    const originalText = button.textContent;
    button.disabled = true;
    button.textContent = loadingText;

    try {
      const response = await fetch("/ops/marketplace_connections", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": this.csrfToken(),
        },
        body: JSON.stringify(payload),
      });

      const data = await this.parseJsonResponse(
        response,
        "submitConnection /ops/marketplace_connections",
      );

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Connection failed");
      }

      if (!data.connect_url) {
        throw new Error("Missing connect URL");
      }

      this.resetForms();
      window.location.href = data.connect_url;
    } catch (error) {
      this.showError(errorBox, error.message || "Connection failed");
      button.disabled = false;
      button.textContent = originalText;
    }
  }

  async deleteConnection(event) {
    const button = event.currentTarget;
    const shopId = button.dataset.shopId;
    const shopName = button.dataset.shopName || "this shop";

    const confirmed = window.confirm(`Delete ${shopName}?`);
    if (!confirmed) return;

    const originalText = button.textContent;
    button.disabled = true;
    button.textContent = "Deleting...";

    try {
      const response = await fetch(`/ops/marketplace_connections/${shopId}`, {
        method: "DELETE",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": this.csrfToken(),
        },
      });

      const data = await this.parseJsonResponse(
        response,
        `deleteConnection /ops/marketplace_connections/${shopId}`,
      );

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Delete failed");
      }

      const card = document.getElementById(`marketplace-shop-${shopId}`);
      if (card) card.remove();
    } catch (error) {
      window.alert(error.message || "Delete failed");
      button.disabled = false;
      button.textContent = originalText;
    }
  }

  async copyTiktokCallback() {
    await this.copyText(
      this.tiktokCallbackValueTarget.textContent.trim(),
      this.tiktokCopyButtonTarget,
    );
  }

  async copyLazadaCallback() {
    await this.copyText(
      this.lazadaCallbackValueTarget.textContent.trim(),
      this.lazadaCopyButtonTarget,
    );
  }

  async copyText(text, button) {
    const originalText = button.textContent;

    try {
      await navigator.clipboard.writeText(text);
      button.textContent = "Copied";
      window.setTimeout(() => {
        button.textContent = originalText;
      }, 1200);
    } catch (_error) {
      button.textContent = "Copy failed";
      window.setTimeout(() => {
        button.textContent = originalText;
      }, 1200);
    }
  }

  resetForms() {
    if (this.hasTiktokShopNameTarget) this.tiktokShopNameTarget.value = "";
    if (this.hasTiktokShopIdTarget) this.tiktokShopIdTarget.value = "";
    if (this.hasTiktokAppKeyTarget) this.tiktokAppKeyTarget.value = "";
    if (this.hasTiktokAppSecretTarget) this.tiktokAppSecretTarget.value = "";

    if (this.hasLazadaShopNameTarget) this.lazadaShopNameTarget.value = "";
    if (this.hasLazadaSellerIdTarget) this.lazadaSellerIdTarget.value = "";
    if (this.hasLazadaAppKeyTarget) this.lazadaAppKeyTarget.value = "";
    if (this.hasLazadaAppSecretTarget) this.lazadaAppSecretTarget.value = "";

    if (this.hasTiktokErrorTarget) this.clearError(this.tiktokErrorTarget);
    if (this.hasLazadaErrorTarget) this.clearError(this.lazadaErrorTarget);
  }

  showError(target, message) {
    target.textContent = message;
    target.classList.remove("is-hidden");
  }

  clearError(target) {
    target.textContent = "";
    target.classList.add("is-hidden");
  }

  csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.content : "";
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
}
