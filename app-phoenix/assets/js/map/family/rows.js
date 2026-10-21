const colors = [
  "#3b82f6",
  "#10b981",
  "#f59e0b",
  "#ef4444",
  "#8b5cf6",
  "#ec4899",
];

export function familyMemberRow(document, location, history, config, center) {
  const node = (tag, classes, text) => {
    const element = document.createElement(tag);
    if (classes) element.setAttribute("class", classes);
    if (text != null) element.textContent = text;
    return element;
  };
  const row = node(
    "div",
    "flex items-center gap-2 p-2 hover:bg-base-200 rounded-lg cursor-pointer transition-colors",
  );
  row.setAttribute("data-family-member-id", String(location.user_id));
  row.setAttribute("role", "button");
  row.setAttribute("tabindex", "0");
  row.addEventListener("click", center);
  row.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      center();
    }
  });
  const index = String(location.user_id)
    .split("")
    .reduce((sum, char) => sum + char.charCodeAt(0), 0);
  const avatar = node(
    "div",
    null,
    (location.name || location.email)?.charAt(0)?.toUpperCase() || "?",
  );
  Object.assign(avatar.style, {
    backgroundColor: colors[index % colors.length],
    color: "white",
    borderRadius: "50%",
    width: "24px",
    height: "24px",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    fontSize: "12px",
    fontWeight: "bold",
    flexShrink: "0",
  });
  const info = node("div", "flex-1 min-w-0");
  info.append(
    node(
      "div",
      "text-sm font-medium truncate",
      location.name || location.email || config.uiLabels?.["common.unknown"],
    ),
  );
  if (location.address) {
    const address = node(
      "div",
      "text-xs text-base-content/70 truncate",
      location.address,
    );
    address.title = location.address;
    info.append(address);
  }
  const stamp = new Date(
    location.updated_at || Number(location.timestamp) * 1000,
  );
  const when = Number.isFinite(stamp.getTime())
    ? stamp.toLocaleString(config.locale, {
        timeZone: config.range?.timezone || "UTC",
        month: "short",
        day: "numeric",
        hour: "numeric",
        minute: "2-digit",
      })
    : "";
  info.append(node("div", "text-xs text-base-content/60", when));
  const status = node("div", "text-xs text-info/70");
  status.setAttribute("data-member-info", String(location.user_id));
  const since = history?.sharing_since && new Date(history.sharing_since);
  if (since && Number.isFinite(since.getTime())) {
    const days = Math.min(
      365,
      Math.floor((Date.now() - since.getTime()) / 86400000),
    );
    const date = since.toLocaleDateString(config.locale, {
      month: "short",
      day: "numeric",
    });
    const text =
      config.uiLabels?.[`family.sharing_since.${days === 1 ? "one" : "other"}`];
    status.setAttribute("data-family-sharing-since", history.sharing_since);
    if (text)
      status.textContent = text
        .replace("{date}", date)
        .replace("{count}", String(days));
  }
  info.append(status);
  row.append(avatar, info);
  return row;
}
