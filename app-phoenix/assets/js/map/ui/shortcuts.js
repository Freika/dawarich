const panels = {
  t: "timeline",
  l: "layers",
  "/": "search",
  c: "tools",
  f: "family",
  s: "settings",
};

export function installHostShortcuts({ root, lifetime }) {
  const document = root?.ownerDocument;
  const keydown = (event) => {
    if (
      event.ctrlKey ||
      event.metaKey ||
      event.altKey ||
      event.repeat ||
      event.defaultPrevented ||
      event.target?.closest?.("input,textarea,select,[contenteditable=true]")
    )
      return;
    const key = event.key?.toLowerCase();
    const selector =
      key === "r"
        ? root.querySelector("[data-map-replay-panel]")?.hidden === false
          ? "[data-map-replay-close]"
          : "[data-map-replay-open]"
        : panels[key] && `[data-testid="map-button-${panels[key]}"]`;
    const control = selector && root?.querySelector(selector);
    if (!control) return;
    event.preventDefault();
    control.click();
  };
  document?.addEventListener?.("keydown", keydown);
  lifetime.own(() => document?.removeEventListener?.("keydown", keydown));
}
