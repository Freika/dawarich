# Mobile family updates

`GET /api/v1/families/mine` advertises `realtime_enabled: true` for an active
family. Clients without this capability continue to poll. Deploy this server
change before expecting realtime updates from a compatible mobile build.

A native client connects to `/cable` with the `actioncable-v1-json` subprotocol,
its usual `Authorization: Bearer <api key>` header, and a same-origin `Origin`
header. API keys in the URL are not accepted. The reverse proxy must support the
existing Action Cable WebSocket upgrade route. Browser session subscriptions
continue to use their existing channels.

After the Action Cable `welcome`, send:

```json
{"command":"subscribe","identifier":"{\"channel\":\"FamilyUpdatesChannel\"}"}
```

The channel sends small invalidation messages in the standard Action Cable
`message` envelope:

- `{"type":"sharing_changed"}` after a committed change to family sharing
  settings. Refresh family metadata, current locations, and visible history.
- `{"type":"locations_changed"}` at most once per five seconds while new
  point broadcasts are arriving. Refresh current locations through the API.
- `{"type":"access_revoked"}` when the API key, membership, or family
  entitlement no longer permits access. Discard displayed family data and close
  the socket. Membership and key validity are also checked every 30 seconds.

No coordinates or member details are transmitted on this channel. HTTP endpoints
remain responsible for applying current membership and sharing permissions.
The API principal cannot subscribe to session-only point, import, track, or
family-location channels. A failed broadcast does not roll back a sharing change.

## Battery constraints for mobile clients

Keep the socket and the 60-second fallback poll active only while the app is in
the foreground and the family map layer is visible. Close on backgrounding,
leaving the map, sign-out, or account change. Use exponential reconnect backoff
and cancel pending retries on close. Mobile connections receive server heartbeats
no more often than every 30 seconds; a compatible client should tolerate this
interval (the app uses a 75-second stale timeout), without sending its own pings.

After explicitly enabling sharing or accepting a location request, the app may
publish one fresh point, respecting existing location permission, the in-app
location setting, and automatic-upload settings. Prefer a cached fix no older
than one minute; otherwise bound a balanced-accuracy location subscription to
10 seconds and remove it after the first fix, cancellation, or timeout. This does
not start ongoing tracking, change the upload batch preference, or flush a backlog.
Opening the family panel refreshes metadata and locations without requesting GPS.

These limits bound extra work; they are not a claim of zero additional energy
usage. Physical-device energy profiling is still needed to quantify the impact.
