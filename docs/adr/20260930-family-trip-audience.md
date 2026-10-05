Status: Implemented
Date: 2026-09-30
Issue: https://github.com/Freika/dawarich/issues/3751

## Context
Family membership does not authorize reading every member's historical trips. The existing shared-trip viewer already scopes route data to a trip and applies the owner's privacy zones. The normal trip viewer embeds an owner API key and must stay owner-only.

## Decision
Add an opt-in family audience to existing SharedLink records: settings.audience = family and settings.family_id = the family at sharing time. A family member sees these shares in a separate section of the Trips list and opens the existing shared-trip viewer under the application layout.
Every HTML, unlock and shared API request checks current membership of both the owner and viewer in the recorded family and Family#access_live?. Family responses use private, no-store caching. A known UUID or magic phrase never substitutes for family membership. The original family ID is retained across URL regeneration; changing families does not transfer consent.

## Alternatives
Automatically exposing all family trips was rejected because membership is not sharing consent. Relaxing TripsController's ownership scope was rejected because it would expose edit/export actions and the owner's API key. Copying trip points into the viewer account was rejected because it would break revocation and duplicate location history.

## Consequences
Public links retain their existing behavior. A trip still has one active share, so selecting family sharing replaces a prior public share. Family viewers cannot edit, export, recalculate or share the owner's trip. Section switches and privacy-zone filtering continue to apply. Family list cards include only the trip name and dates, never the unmasked stored path.
The viewer can open their own map for the same dates. This does not merge or copy the owner's points. Multi-device tracking remains supported by the existing tracker/source model.
Membership departure, owner departure, share expiry, revocation and family entitlement lapse revoke access. A URL already known by a viewer is reauthorized on each request. No database migration is required.

## Verification
spec/requests/family_trip_sharing_spec.rb covers creation, listing, authorization, private caching, date scoping, route exclusion, privacy zones, membership departure, owner family change, entitlement lapse, expiry and revocation.
Browser checks exercised creating a family share, viewing it as a second member, rendering the route and revoking access.
Local source: docs/adr/20260930-family-trip-audience.md in fix/issues-3751-3752-3754-3756.
