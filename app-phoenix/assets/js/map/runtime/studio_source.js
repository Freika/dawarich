import { readRouteSnapshot } from "../data/route_snapshot.js";
import { createStudioSource } from "../data/studio_source.js";

export function installHostSource({ owner, reader, requests, onDestroy }) {
  const snapshotReader = reader.fork?.() ?? reader;
  owner.source = createStudioSource({
    getState: () => owner.config,
    readSnapshot: (state, options) =>
      readRouteSnapshot(snapshotReader, state, options),
    applyDates: requests.applyDates,
  });
  const dispose = owner.destroy;
  owner.destroy = () => {
    onDestroy?.();
    requests.destroy();
    owner.source.destroy();
    if (snapshotReader !== reader) snapshotReader.destroy();
    dispose();
  };
}
