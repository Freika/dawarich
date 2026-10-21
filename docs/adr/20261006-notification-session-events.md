Status: Accepted
Date: 2026-10-06

## Context

Plan B N02 requires connected notification events to refuse writes after native logout in another tab. Rails uses an encrypted stateless session cookie; A11 owns authentication and current-key storage. The notification producer must not introduce a second persistent session authority or duplicate the existing Cable delivery path.

## Decision

Successful native logout publishes a session-local signal through the existing Phoenix PubSub. Connected authenticated navbar views subscribe when mounting and check the signal plus current account/password authority before their application events. The topic is a SHA-256 digest of the actor and existing Rails CSRF identity, falling back to session ID. LayoutAssigns creates missing CSRF identity before the LiveView session is built. Prefer that identity because RailsSession may add a session ID when rewriting an older cookie; cookie rewriting must not disconnect the logout signal.

Native notification updates append the existing durable notification event in their transaction. Connected views consume the existing Cable bus and reload owned cards/unread counts. Session-authorized API-key rotation locks and verifies the current session actor and shares A11's existing persistence/entropy primitive; it accepts already authenticated provider/OTP actors without weakening A11's separate bounded entry point.

## Alternatives considered

Polling alone does not exercise durable update publication or immediate logout refusal. A new Redis/SQL revocation registry would create an additional authentication owner and alter Rails' stateless semantics. Request-supplied user IDs cannot select the target of session-authorized key rotation. These alternatives were rejected for this package.

## Consequences and limits

This is a connected-view logout signal, not persistent invalidation of copied stateless cookies or a cross-node session registry. Fresh connections remain subject to existing SessionStore/RailsAuth authentication. Retained Rails logout does not emit the native signal. Authentication and infrastructure ownership remain with A11 and the controller. HOT mounts the separate route modules; no shared router is changed here.

## Implementation and verification

Implementation: NotificationSession, AuthHandler, RailsAuth.live_session, LiveAuth, NavbarHooks, Auth.ApiKeys.rotate_session. Repository runbook: docs/phoenix/a12f3b-settings.md. Regression selectors N02a/N02b prove real Cable delivery, an actual native logout with the rewritten response cookie, refusal before row mutation, and failing named mutations followed by restored GREEN. N05a proves actor scope, previous-key invalidation and provider/OTP support. Full release gate evidence is recorded in the controller-assigned package report.

Related AFFiNE runbook: sIL5FiAZt9ZWDGTJTbQ2O. The Cloud operator-grant ADR lhm4h4Ab4OmJufkmL-5dR governs a separate privileged boundary; this decision neither replaces nor broadens it.
