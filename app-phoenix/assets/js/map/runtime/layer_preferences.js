export function createLayerPreferences({ namespace, initial, onRestore }) {
  let active = true;
  const key = namespace && `dawarich:map:${namespace}:anomalies`;
  let preferred =
    initial.anomaliesPreferred ?? initial.anomaliesEnabled === true;
  if (key) {
    try {
      const saved = globalThis.localStorage?.getItem(key);
      if (saved === "true" || saved === "false") {
        preferred = saved === "true";
        queueMicrotask(() => {
          if (active) onRestore?.(preferred);
        });
      }
    } catch {}
  }
  function configure(config) {
    preferred = config.anomaliesPreferred ?? preferred;
    return {
      ...config,
      anomaliesPreferred: preferred,
      anomaliesEnabled: preferred && config.pointsEnabled !== false,
    };
  }
  return {
    destroy() {
      active = false;
    },
    initial: configure({ ...initial, anomaliesPreferred: preferred }),
    update(config) {
      const next = configure(config);
      if (key) {
        try {
          globalThis.localStorage?.setItem(key, String(preferred));
        } catch {}
      }
      return next;
    },
  };
}
