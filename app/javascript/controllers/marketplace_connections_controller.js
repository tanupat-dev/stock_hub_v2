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

      const data = await response.json();

      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Connection failed");
      }

      if (!data.connect_url) {
        throw new Error("Missing connect URL");
      }

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

      const data = await response.json();

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
}
