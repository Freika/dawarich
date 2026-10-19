import { createRequestScope } from "../data/request_scope.js";
import { createFamilyOverlay } from "./overlay.js";

export function createMapFamilyLayer({
  map,
  reader,
  library,
  root,
  timers = globalThis,
  createOverlay = createFamilyOverlay,
}) {
  const requests = createRequestScope(timers);
  let overlay,
    overlayLocale,
    config,
    destroyed = false,
    rendered;
  const list = () => root?.querySelector("#native-family-members");
  const status = () => root?.querySelector("#native-family-status");
  const empty = () => root?.querySelector("[data-map-family-empty]");
  function clearView() {
    rendered = null;
    overlay?.clear();
    list()?.replaceChildren();
    if (list()) list().hidden = true;
    if (status()) status().textContent = "";
    if (empty()) empty().hidden = !config?.familyEnabled;
  }
  const scope = (value) => JSON.stringify([
    value?.familyEnabled, value?.namespace, value?.range, value?.locale,
  ]);
  function clear(next) {
    const preserve = next && config && scope(next) === scope(config);
    if (next) config = next;
    requests.reset();
    if (!preserve) clearView();
    if (!config?.familyEnabled) {
      overlay?.destroy();
      overlay = null;
    }
  }
  function render(rows, members) {
    const container = list();
    if (!container) return;
    const signature = JSON.stringify([
      rows, members, config.locale, config.range?.timezone, config.uiLabels,
      members.map(({ sharing_since: since }) =>
        Math.min(365, Math.floor((Date.now() - Date.parse(since)) / 86400000)),
      ),
    ]);
    if (rendered?.container === container && rendered.signature === signature) return;
    rendered = { container, signature };
    const document = root.ownerDocument;
    container.replaceChildren(
      ...rows.map((row) => {
        const button = document.createElement("button");
        button.setAttribute("type", "button");
        button.setAttribute(
          "class",
          "btn btn-ghost h-auto w-full justify-start text-left whitespace-normal [overflow-wrap:anywhere]",
        );
        button.setAttribute("data-family-member-id", String(row.user_id));
        const stamp = new Date(row.updated_at || Number(row.timestamp) * 1000);
        const when = Number.isFinite(stamp.getTime())
          ? new Intl.DateTimeFormat(config.locale, {
              month: "short",
              day: "numeric",
              hour: "numeric",
              minute: "2-digit",
              timeZone: config.range?.timezone || "UTC",
            }).format(stamp)
          : "";
        button.textContent = `${row.name || row.email || ""} · ${when}`;
        if (row.address) {
          const address = document.createElement("span");
          address.setAttribute(
            "class",
            "block text-xs w-full [overflow-wrap:anywhere]",
          );
          address.textContent = row.address;
          button.append(address);
        }
        button.addEventListener("click", () => {
          if (destroyed || !config.familyEnabled || !container.isConnected)
            return;
          map.flyTo({ center: [row.longitude, row.latitude], zoom: 15 });
          if (status())
            status().textContent =
              status().dataset.centered ||
              config.uiLabels?.["messages.centered_on_family_member"] ||
              "";
        });
        const history = members.find(
          (member) => member.user_id === row.user_id,
        );
        const since = history?.sharing_since && new Date(history.sharing_since);
        if (since && Number.isFinite(since.getTime())) {
          const days = Math.min(
            365,
            Math.floor((Date.now() - since.getTime()) / 86400000),
          );
          const date = new Intl.DateTimeFormat(config.locale, {
            month: "short",
            day: "numeric",
          }).format(since);
          const text =
            config.uiLabels?.[
              `family.sharing_since.${days === 1 ? "one" : "other"}`
            ];
          if (text) {
            const info = document.createElement("span");
            info.setAttribute("data-member-info", String(row.user_id));
            info.setAttribute(
              "data-family-sharing-since",
              history.sharing_since,
            );
            info.setAttribute(
              "class",
              "block text-xs w-full [overflow-wrap:anywhere]",
            );
            info.textContent = text
              .replace("{date}", date)
              .replace("{count}", String(days));
            button.append(info);
          }
        }
        return button;
      }),
    );
    container.hidden = rows.length === 0;
    if (empty()) empty().hidden = rows.length > 0;
    const loaded =
      config.uiLabels?.[
        `family.loaded_members.${rows.length === 1 ? "one" : "other"}`
      ];
    if (status() && rows.length > 0 && loaded)
      status().textContent = loaded.replace("{count}", String(rows.length));
  }
  async function update(next, { signal } = {}) {
    if (destroyed) return;
    clear(next);
    if (!config.familyEnabled) return;
    if (!overlay || overlayLocale !== config.locale) {
      overlay?.destroy();
      overlay = createOverlay({
        map,
        library,
        locale: config.locale,
        timers,
        colorMode: "id",
      });
      overlayLocale = config.locale;
    }
    const operation = requests.begin(signal);
    try {
      const [latest, history] = await operation.wait(
        Promise.all([
          reader.read("family_locations", {}, { signal: operation.signal }),
          config.range?.startAt && config.range?.endAt
            ? reader.read(
                "family_history",
                { start_at: config.range.startAt, end_at: config.range.endAt },
                { signal: operation.signal },
              )
            : Promise.resolve({ data: { members: [] } }),
        ]),
      );
      operation.check();
      const rows = (latest.data.locations || []).filter(
        (row) =>
          Number.isFinite(row.longitude) &&
          Number.isFinite(row.latitude) &&
          Math.abs(row.longitude) <= 180 &&
          Math.abs(row.latitude) <= 90,
      );
      overlay.replace(rows, history.data.members || []);
      render(rows, history.data.members || []);
    } catch {
      if (operation.revision === requests.revision) clearView();
    } finally {
      operation.close();
    }
  }
  return {
    update,
    clear,
    destroy() {
      if (destroyed) return;
      destroyed = true;
      requests.destroy();
      clearView();
      overlay?.destroy();
      overlay = null;
    },
  };
}
