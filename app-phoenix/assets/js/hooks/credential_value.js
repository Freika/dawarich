export const CredentialValue = {
  mounted() {
    this.generation = 0;
    this.clear = () => {
      this.generation++;
      this.request?.abort();
      this.request = null;
      this.el.textContent = "";
    };
    this.reveal = async () => {
      this.clear();
      const generation = this.generation;
      const request = new AbortController();
      this.request = request;
      try {
        const response = await fetch("/native/account/key", {
          credentials: "same-origin",
          cache: "no-store",
          signal: request.signal,
          headers: {
            "X-CSRF-Token":
              document.querySelector('meta[name="csrf-token"]')?.content || "",
          },
        });
        if (!response.ok) return;
        const { api_key: key } = await response.json();
        if (generation !== this.generation || request.signal.aborted || !key)
          return;
        this.el.textContent = this.el.dataset.path
          ? `${this.el.dataset.path}?api_key=${encodeURIComponent(key)}`
          : key;
      } catch {
        if (generation === this.generation) this.clear();
      } finally {
        if (this.request === request) this.request = null;
      }
    };
    this.onPageReady = () => {
      if (this.el.isConnected) this.reveal();
    };
    globalThis.window?.addEventListener("phx:page-loading-start", this.clear);
    globalThis.window?.addEventListener(
      "phx:page-loading-stop",
      this.onPageReady,
    );
    this.handleEvent("refresh-account-credentials", this.reveal);
    this.reveal();
  },
  beforeUpdate() {
    this.clear();
  },
  updated() {
    this.reveal();
  },
  disconnected() {
    this.clear();
  },
  destroyed() {
    this.clear();
    globalThis.window?.removeEventListener(
      "phx:page-loading-start",
      this.clear,
    );
    globalThis.window?.removeEventListener(
      "phx:page-loading-stop",
      this.onPageReady,
    );
  },
};
