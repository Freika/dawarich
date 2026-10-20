import { createRequestScope } from "../data/request_scope.js";
import { createFamilyOverlay } from "./overlay.js";
import { familyMemberRow } from "./rows.js";
import { mapNotify } from "../ui/notify.js";

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
  const notify = mapNotify(() => config);
  const group = () => root?.querySelector("#native-family-list");
  function clearView() {
    rendered = null;
    overlay?.clear();
    list()?.replaceChildren();
    if (list()) list().hidden = true;
    if (group()) group().style.display = "none";
  }
  const scope = (value) =>
    JSON.stringify([
      value?.familyEnabled,
      value?.namespace,
      value?.range,
      value?.locale,
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
      rows,
      members,
      config.locale,
      config.range?.timezone,
      config.uiLabels,
      members.map(({ sharing_since: since }) =>
        Math.min(365, Math.floor((Date.now() - Date.parse(since)) / 86400000)),
      ),
    ]);
    if (rendered?.container === container && rendered.signature === signature)
      return;
    rendered = { container, signature };
    const document = root.ownerDocument;
    container.replaceChildren(
      ...rows.map((row) => {
        return familyMemberRow(
          document,
          row,
          members.find((member) => member.user_id === row.user_id),
          config,
          () => {
            if (destroyed || !config.familyEnabled || !container.isConnected)
              return;
            map.flyTo({
              center: [row.longitude, row.latitude],
              zoom: 15,
              duration: 1500,
            });
            void notify("success", "messages.centered_on_family_member");
          },
        );
      }),
    );
    container.hidden = false;
    if (group()) group().style.display = "block";
    if (rows.length === 0) {
      const empty = document.createElement("p");
      empty.setAttribute("class", "text-xs text-base-content/60");
      empty.textContent = config.uiLabels?.["family.none_sharing"] || "";
      container.replaceChildren(empty);
    }
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
      const latest = await operation.wait(
        reader.read("family_locations", {}, { signal: operation.signal }),
      );
      operation.check();
      void notify("success", "family.loaded_members", {
        count: (latest.data.locations || []).length,
      });
      const history =
        config.range?.startAt && config.range?.endAt
          ? await operation.wait(
              reader
                .read(
                  "family_history",
                  {
                    start_at: config.range.startAt,
                    end_at: config.range.endAt,
                  },
                  { signal: operation.signal },
                )
                .catch(() => ({ data: { members: [] } })),
            )
          : { data: { members: [] } };
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
    } catch (error) {
      if (operation.revision === requests.revision) {
        clearView();
        if (!operation.signal.aborted)
          void notify(
            error.status === 403 ? "info" : "error",
            error.status === 403
              ? "messages.family_feature_not_available"
              : "messages.failed_to_load_family_members",
          );
      }
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
