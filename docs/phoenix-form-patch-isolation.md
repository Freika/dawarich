# Ordinary forms inside native pages

LiveView's connected render starts from persisted assigns. An ordinary browser/Turbo/Stimulus form does not send edits through `phx-change`, so a patch can restore server defaults while a user is editing, especially a selected option or checkbox before the initial join. Put editable forms in an island with a deterministic, unique `id` and `phx-update="ignore"`. Existing keyed field islands are also valid. LiveView-bound forms must remain patchable. Turbo document/frame/stream responses still own ordinary form validation and replacement.

The shared `Dawarich.Test.FormIsolation.assert_form_isolated/2` checks rendered forms, including ignored ancestors and field islands. Every editable input, select, textarea and Trix editor must have a keyed ignored owner; that owner's id must occur exactly once. The import regression checks the same record-specific form id before join, after join and after rendering again. Points keep their page-specific owner so pagination can replace the island.

Audit: `rg -n '<\.?form\b' app-phoenix/lib/dawarich_web` on the fix-formiso branch. Paths below are relative to that directory. Each row covers every form in that file; mixed cases are explicit. Bound forms and GET/dialog/controller-only forms are included to make exclusions reviewable. “Protected already” means no production change was required; tests now share the isolation assertion.

| Renderer / forms | Classification | Isolation or reason |
| --- | --- | --- |
| `components/import_edit.ex` rename/source PATCH | Protected now | `phx-import-edit-<record id>` form ignores patches; named before/after-join regression. |
| `settings_live/user_edit.ex` user PUT | Protected now | Existing `edit_user_<id>` form now ignores patches. |
| `settings_live/users_index.ex` registration PATCH | Protected now | `phx-registration-settings` form ignores patches. |
| `components/admin_instance/pane.html.heex` instance PATCH | Protected now | `phx-instance-settings-<section>` form ignores patches. |
| `settings_live/visits.ex` detection PATCH | Protected already | `phx-visit-detection-settings` form. |
| `settings_live/general.ex` general PATCH | Protected already | Keyed ignored language radios, timezone select and toggle inputs from `SettingsParts`. |
| `components/integration_panes.ex` integration PATCH | Protected already | Keyed ignored integration fields; Teslamate fields use the same contract. Sync POST has only a button/CSRF, so needs no edit isolation. |
| `components/supporter_card.ex` verification POST | Protected already | Keyed ignored email and GitHub username fields. |
| `components/trek_pane.ex` source POST | Protected already | `trek-source-form` ancestor. Sync POST and DELETE have no editable inputs. |
| `components/account_profile.ex` account PUT | Protected already | `edit_user` form. |
| `components/account_parts.ex` import POST | Protected already | `import_modal` dialog ancestor; dialog backdrop has no server submission. |
| `components/danger_zone.ex` account DELETE | Protected already | `delete_account_modal` ancestor covers password/email confirmation; dialog backdrop only closes. |
| `imports_live/new.ex` upload POST via Stimulus | Protected already | `phx-import-upload` form. |
| `components/imports_extraction_dialog.ex` extraction POST | Protected already | `extraction-dialog-<id>` ancestor covers checkboxes; dialog backdrop only closes. |
| `components/admin_user_dialogs.ex` create POST | Protected already | `create_user` dialog ancestor. User DELETE has no editable input; dialog forms only close. |
| `components/tag_form.ex` tag POST/PATCH | Protected already | `tag-fields-<id or new>` island includes name and pickers. |
| `components/point_list_table.ex` bulk DELETE | Protected already | `points-page-<page identity>` ancestor owns selection checkboxes. |
| `components/family_forms.ex` create POST/edit PATCH | Protected already | `family-form-shell` ancestor. |
| `components/family_controls.ex` sharing PATCH | Protected already | `family-shell` or `family-form-shell` ancestor. |
| `components/family_members.ex` invitation POST | Protected already | `family-shell` / `family-invitations-shell` ancestor covers invitation email. Location-request POST and invitation DELETE have no editable input. |
| `components/family_request_forms.ex` acceptance PATCH | Protected already | `family-request-shell` ancestor covers duration. Decline PATCH has no editable input. |
| `components/trip_form.ex` trip POST/PATCH | Protected already | `trip-form-shell` ancestor covers fields and Trix editor. |
| `components/trip_note_form.ex` note POST/PATCH | Protected already | `trip-shell` ancestor; standalone Turbo note responses are not LiveViews. |
| `components/sharing_parts.ex` sharing PATCH | Protected already | `sharing_modal` dialog ancestor; closing form is dialog-only. |
| `components/share_link_form/create_form.html.heex` create POST | Protected already | `share-link-modal` frame island; standalone full documents have no LiveView join. |
| `components/map_modals.ex` visit POST via Stimulus / area POST | Protected already | `map-shell` ancestor. |
| `components/map_place_modal.ex` place POST | Protected already | `map-shell` ancestor. |
| `components/map_panel.ex` settings PATCH via Stimulus | Protected already | `map-shell` ancestor. |
| `components/poster_studio_actions.ex` poster POST | Protected already | `map-shell` / `trip-shell` ancestor also owns controller-populated hidden fields. |
| `components/timeline_entries.ex` rename PATCH | Protected already | Rendered inside `map-shell`; standalone Turbo responses have no join. Visit DELETE has no editable input. |
| `components/timeline_feed.ex` merge POST/bulk DELETE | Protected already | `map-shell` owns selection and controller-populated payload; standalone frame responses have no join. |
| `components/segment_row.ex` mode PATCH | Protected already | `map-shell` ancestor; standalone Turbo row responses have no join. |
| `components/segment_legs.ex` mode PATCH | Protected already | `map-shell` ancestor; standalone Turbo leg responses have no join. |
| `components/place_drawer_frame.ex` note POST | Protected already | Drawer is inserted into `map-shell`; standalone Turbo responses have no join. Place DELETE has no editable input. |
| `achievement_sharing_controls.ex` sharing PATCH ×2 | Not needed | Buttons and hidden payload only; enclosing achievement shell is already ignored. |
| `components/admin_instance/geocoding_status.html.heex` test POST | Not needed | Button and CSRF only. |
| `components/digest_parts.ex` digest POST | Not needed | Regeneration button and CSRF only. |
| `components/imports_extraction_card.ex` extraction DELETE | Not needed | Remove button and hidden payload only. |
| `components/share_hub/shared_list.html.heex` revoke PATCH | Not needed | Button and hidden payload only. |
| `components/share_link_active.ex` active-link POST/PATCH/DELETE | Not needed | Button and hidden payload only. |
| `components/map_settings_more.ex` recalculation POST | Not needed | Button and hidden payload only. |
| `components/trip_parts.ex` trip DELETE/recalculate POST | Not needed | Buttons and hidden payload only. |
| `components/trip_days_list.ex` note DELETE | Not needed | Button and hidden payload only; note editors covered above. |
| `components/visit_redetect_panel.ex` redetection POST | Not needed | Button and CSRF only. |
| `layouts/map.html.heex` demo DELETE | Not needed | Button and hidden payload only; banner already ignored. |
| `settings_live/user_show/show.html.heex` key regeneration/reset POST | Not needed | Buttons and CSRF only. |
| `tags_live/index.ex` tag DELETE | Not needed | Button and hidden payload only. |
| `auth_form.ex` sign-in POST | Not needed | HTTP-rendered authentication document, no LiveView mount. |
| `auth_recovery/form.ex` recovery POST/PUT | Not needed | HTTP-rendered authentication document, no LiveView mount. |
| `auth_otp/form/challenge.html.heex` OTP POST | Not needed | HTTP-rendered authentication document, no LiveView mount. |
| `auth_account_link/form/challenge.html.heex` challenge/email POST | Not needed | HTTP-rendered authentication document, no LiveView mount. |
| `auth_two_factor/form/show.html.heex` enable POST/disable DELETE | Not needed | HTTP-rendered authentication document, no LiveView mount. |
| `auth_two_factor/form/verify.html.heex` verification POST | Not needed | HTTP-rendered authentication document, no LiveView mount. |
| `shared_pages/phrase_prompt.html.heex` unlock POST | Not needed | HTTP-rendered shared page, no LiveView mount. |
| `achievement_children.ex` collection GET | Not needed for write audit | GET search/filter; keyed ignored fields already protect edits. |
| `components/map_controls.ex` date GET | Not needed for write audit | GET form within ignored `map-shell`. |
| `components/point_list_controls.ex` filter GET | Not needed for write audit | GET controls outside the requested POST/PATCH/DELETE audit. |
| `settings_live/users_index.ex` search GET | Not needed for write audit | Separate GET search form. |
| `components/onboarding_screens.ex` import via Stimulus | Protected already | `onboarding-modal` ancestor; upload selection survives join. |
| `components/onboarding_modal.ex` close dialog | Not needed | `method=dialog`, no server submission. |
| `components/stats_cards.ex` close dialogs ×2 | Not needed | `method=dialog`, no server submission. |
| `notifications_live/show.ex` DELETE | Not needed | Bound to `phx-submit="destroy"`; LiveView owns it. |
| `imports_live/show.ex` DELETE | Not needed | Bound to `phx-submit="delete_import"`; LiveView owns it. |
| `components/import_row.ex` DELETE | Not needed | Bound to `phx-submit="delete_import"`; LiveView owns it. |
| `components/navbar_parts.ex` consent PATCH | Not needed | Bound to `phx-submit="changelog_consent"`; LiveView owns it. |

Verification lives in the existing page tests: imports, admin parity, settings, visits, points, tags, onboarding, family, map, trip navigation/show parity and share-management pages. No authentication controller or POST behavior changed. Browser gates exercise import lifecycle three separate times ON and once OFF, plus visits/settings, points/list and tags/crud ON.
