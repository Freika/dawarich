| file | current case (before conversion) | needs_real_commits | reason |
| --- | --- | --- | --- |
| dawarich/a12f3b_e061_cloud_guard_test.exs | Dawarich.DataCase | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/account_api/exist_test.exs | Dawarich.IngestCase | no | Reviewed same-process queries/DML or timezone parsing; transaction-local fixtures and no shared-state mutation |
| dawarich/account_api/payload_test.exs | Dawarich.IngestCase | no | Reviewed same-process queries/DML or timezone parsing; transaction-local fixtures and no shared-state mutation |
| dawarich/achievement_checks_migration_test.exs | Dawarich.ScratchCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/achievements/bulk_check_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/achievements/celebrations_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/achievements/collection_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/achievements/deck_claim_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/achievements/deck_seen_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/achievements/public_card_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/achievements/sharing_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/achievements/ui_silhouettes_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/achievements/ui_text_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/achievements/unlock_card_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/admin/instance_page_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/admin/instance_writes_test.exs | ExUnit.Case | yes | Redis/cache helpers may use shared keys; namespacing not proven |
| dawarich/admin/job_health_test.exs | Dawarich.JobsCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/admin/setting_writes_test.exs | ExUnit.Case | yes | Redis/cache helpers may use shared keys; namespacing not proven |
| dawarich/admin/user_create_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/admin/user_roles_test.exs | ExUnit.Case | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich/admin/user_security_test.exs | ExUnit.Case | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich/admin/user_update_test.exs | ExUnit.Case | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich/admin/users_page_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/air_trail/client_test.exs | ExUnit.Case | no | Client talks to listeners it opens on port 0 and owns; no database, env or global state |
| dawarich/air_trail/import_flights_worker_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/air_trail/sync_scheduling_worker_test.exs | Dawarich.JobsCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/app_version/check_worker_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/app_version_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/application_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/auth/account_changes_test.exs | ExUnit.Case | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich/auth/account_link/concurrency_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/auth/account_link/confirmation_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/auth/account_link/pending_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/auth/account_link/sign_in_test.exs | ExUnit.Case | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/auth/api/challenge_cache_test.exs | ExUnit.Case | yes | Redis/cache helpers may use shared keys; namespacing not proven |
| dawarich/auth/api/challenge_concurrency_test.exs | ExUnit.Case | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/auth/api/challenge_test.exs | ExUnit.Case | yes | Redis/cache helpers may use shared keys; namespacing not proven |
| dawarich/auth/api/challenge_verify_test.exs | ExUnit.Case | yes | Redis/cache helpers may use shared keys; namespacing not proven |
| dawarich/auth/api/challenge_write_test.exs | ExUnit.Case | yes | Redis/cache helpers may use shared keys; namespacing not proven |
| dawarich/auth/api/login_test.exs | ExUnit.Case | no | Own sandbox checkout; password-work file uses a unique System.tmp_dir path; persistent_term holds only deterministic derived keys; no env, Redis or real commits |
| dawarich/auth/api/payload_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/auth/api_keys_test.exs | ExUnit.Case | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich/auth/auth_handler_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/auth/credentials_test.exs | ExUnit.Case | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/auth/http_boundary_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/auth/otp/completion_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/auth/otp/start_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/auth/recovery/concurrency_test.exs | ExUnit.Case | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/auth/recovery/flow_test.exs | ExUnit.Case | no | Own sandbox checkout; row locks only on rows the test inserted; persistent_term holds deterministic token keys; no env, Redis or real commits |
| dawarich/auth/recovery/http_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/auth/recovery/lifecycle_test.exs | ExUnit.Case | no | Own sandbox checkout; row locks only on rows the test inserted; persistent_term holds deterministic token keys; no env, Redis or real commits |
| dawarich/auth/recovery/mail_worker_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/auth/registration_setting_redis_test.exs | Dawarich.JobsCase | yes | Redis/cache helpers may use shared keys; namespacing not proven |
| dawarich/auth/registration_setting_test.exs | Dawarich.JobsCase | yes | Redis/cache helpers may use shared keys; namespacing not proven |
| dawarich/auth/two_factor/api_actor_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/auth/two_factor/api_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/auth/two_factor/management_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/auth/two_factor/secret_test.exs | ExUnit.Case | no | Own sandbox checkout; capture_log without changing the Logger level; persistent_term holds deterministic encryption keys; no env or real commits |
| dawarich/build/rails_parity_test.exs | ExUnit.Case | yes | Uses Rails parity or an external process/peer |
| dawarich/cable/bus_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/cable/channels_test.exs | Dawarich.IngestCase | yes | Shared sandbox or ingestion helpers may reach other processes/global sources; conservatively retain |
| dawarich/cable/events_relay_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/cable/identity_test.exs | Dawarich.IngestCase | yes | Shared sandbox or ingestion helpers may reach other processes/global sources; conservatively retain |
| dawarich/cable/pg_bus_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/cable/pg_retention_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/cable/pg_store_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/cable/pg_turbo_events_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/cable/turbo_events_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/cable_pg_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/cable_test.exs | ExUnit.Case | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/cache/preheat_digests_test.exs | Dawarich.JobsCase | yes | Digest corpus/helper can alter indexes or table constraints; retain conservatively |
| dawarich/cache/preheat_sweep_worker_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/cache/preheat_user_worker_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/cache/schedule_test.exs | Dawarich.JobsCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/cli/arguments_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/cli/jobs_test.exs | Dawarich.JobsCase | yes | Exercises real queue services or scheduling |
| dawarich/cli/migrate_test.exs | ExUnit.Case | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/cli/raw_data_reset_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/cli/raw_data_storage_test.exs | ExUnit.Case | yes | Writes files or shared build/output state; isolation not proven |
| dawarich/cli/users_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/cli_parity_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/cloud/endpoint_url_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/countries_and_cities_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich/digests/activity_test.exs | Dawarich.JobsCase | yes | Digest corpus/helper can alter indexes or table constraints; retain conservatively |
| dawarich/digests/api_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich/digests/calculate_month_test.exs | Dawarich.JobsCase | yes | Digest corpus/helper can alter indexes or table constraints; retain conservatively |
| dawarich/digests/calculate_year_test.exs | Dawarich.JobsCase | yes | Digest corpus/helper can alter indexes or table constraints; retain conservatively |
| dawarich/digests/calculation_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/digests/comparison_test.exs | Dawarich.JobsCase | no | Reviewed selected fixture cases: same-process queries and DML only; no legacy DDL fixtures |
| dawarich/digests/concurrency_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/digests/corpus_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/digests/failure_test.exs | Dawarich.JobsCase | yes | Digest corpus/helper can alter indexes or table constraints; retain conservatively |
| dawarich/digests/generation_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/digests/job_entries_test.exs | Dawarich.JobsCase | yes | Uses Rails parity or an external process/peer |
| dawarich/digests/job_lifecycle_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/digests/jobs_corpus_test.exs | Dawarich.JobsCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/digests/location_time_test.exs | Dawarich.JobsCase | no | Reviewed selected fixture cases: same-process queries and DML only; no legacy DDL fixtures |
| dawarich/digests/period_test.exs | Dawarich.JobsCase | no | Reviewed selected fixture cases: same-process queries and DML only; no legacy DDL fixtures |
| dawarich/digests/queries_test.exs | Dawarich.JobsCase | no | Reviewed selected fixture cases: same-process queries and DML only; no legacy DDL fixtures |
| dawarich/digests/read_consumers_test.exs | Dawarich.IngestCase | yes | Digest corpus/helper can alter indexes or table constraints; retain conservatively |
| dawarich/digests/run_test.exs | Dawarich.JobsCase | yes | Digest corpus/helper can alter indexes or table constraints; retain conservatively |
| dawarich/digests/schedule_test.exs | Dawarich.JobsCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/digests/scheduling_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/digests/seasonality_test.exs | Dawarich.JobsCase | no | Reviewed selected fixture cases: same-process queries and DML only; no legacy DDL fixtures |
| dawarich/digests/store_test.exs | Dawarich.JobsCase | yes | Digest corpus/helper can alter indexes or table constraints; retain conservatively |
| dawarich/digests/time_of_day_test.exs | Dawarich.JobsCase | no | Reviewed selected fixture cases: same-process queries and DML only; no legacy DDL fixtures |
| dawarich/digests/workers_test.exs | Dawarich.JobsCase | yes | Exercises real queue services or scheduling |
| dawarich/enhanced_import/destroy_gpx_worker_test.exs | Dawarich.EnhancedImportCase | yes | Exercises real queue services or scheduling |
| dawarich/enhanced_import/extract_gpx_worker_test.exs | Dawarich.EnhancedImportCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/enhanced_import/extraction_deadline_test.exs | Dawarich.EnhancedImportCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/enhanced_import/gpx_test.exs | Dawarich.EnhancedImportCase | yes | Writes files or shared build/output state; isolation not proven |
| dawarich/enhanced_import/place_writer_test.exs | Dawarich.EnhancedImportCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/enhanced_import/source_file_test.exs | Dawarich.EnhancedImportCase | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich/exports/points_time_zone_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/exports/points_worker_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/families/auto_create_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/families/history_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich/families/job_workers_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/families/member_sync_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/families/sharing_update_test.exs | Dawarich.IngestCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/family_page_test.exs | ExUnit.Case | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich/flights_test.exs | Dawarich.IngestCase | no | Reviewed same-process queries and timezone parsing; fixtures are read-only and session settings are transaction-local |
| dawarich/geocoding/config_test.exs | Dawarich.GeocodingCase | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich/geocoding/countries_test.exs | Dawarich.GeocodingCase | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich/geocoding/place_fetch_test.exs | Dawarich.GeocodingCase | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich/geocoding/point_fetch_test.exs | Dawarich.GeocodingCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/geocoding/rate_limiter_test.exs | ExUnit.Case | yes | Redis/cache helpers may use shared keys; namespacing not proven |
| dawarich/geocoding/response_cache_test.exs | ExUnit.Case | yes | Mutates shared persistent terms or ETS caches |
| dawarich/geocoding/reverse_place_worker_test.exs | Dawarich.GeocodingCase | yes | Exercises real queue services or scheduling |
| dawarich/geocoding/reverse_point_worker_test.exs | Dawarich.GeocodingCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/geocoding/search_test.exs | Dawarich.GeocodingCase | yes | Redis/cache helpers may use shared keys; namespacing not proven |
| dawarich/import_export_index_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/imports/activity_backfill/phone_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/imports/activity_backfill/semantic_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/imports/activity_backfiller_test.exs | Dawarich.JobsCase | yes | Writes files or shared build/output state; isolation not proven |
| dawarich/imports/archive_dispatch_test.exs | ExUnit.Case | yes | Writes files or shared build/output state; isolation not proven |
| dawarich/imports/bulk_writer_failure_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/imports/bulk_writer_test.exs | Dawarich.IngestCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/imports/csv_records_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/imports/csv_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/imports/destroy_legacy_schema_test.exs | Dawarich.IngestCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/imports/destroy_recovery_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/imports/destroy_test.exs | Dawarich.JobsCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/imports/destroy_worker_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/imports/download_blob_store_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/imports/download_producer_test.exs | Dawarich.JobsCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/imports/download_stream_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/imports/download_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/imports/fit_reader_test.exs | ExUnit.Case | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich/imports/fit_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/imports/geojson_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/imports/google_phone_points_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/imports/google_phone_stream_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/imports/google_phone_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/imports/google_records_point_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/imports/google_records_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/imports/google_semantic_history_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/imports/gpx_fence_test.exs | Dawarich.JobsCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/imports/gpx_importer_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/imports/gpx_lifecycle_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/imports/gpx_numeric_persistence_test.exs | Dawarich.JobsCase | yes | Writes files or shared build/output state; isolation not proven |
| dawarich/imports/gpx_point_test.exs | Dawarich.IngestCase | no | Reviewed same-process queries and timezone parsing; fixtures are read-only and session settings are transaction-local |
| dawarich/imports/gpx_progress_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/imports/immich_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/imports/import_state_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/imports/import_time_test.exs | Dawarich.IngestCase | no | Reviewed same-process queries and timezone parsing; fixtures are read-only and session settings are transaction-local |
| dawarich/imports/json_stream_test.exs | ExUnit.Case | no | Pure parser over ExUnit tmp_dir files; no database, env or global state |
| dawarich/imports/kml_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/imports/kmz_test.exs | Dawarich.JobsCase | yes | Writes files or shared build/output state; isolation not proven |
| dawarich/imports/lease_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/imports/mobile_photo_library_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/imports/normal_batch_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/imports/normal_lifecycle_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/imports/normal_upload_test.exs | Dawarich.JobsCase, Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/imports/normal_writer_oracle_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich/imports/owntracks_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/imports/photoprism_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/imports/photos_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/imports/polarsteps_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/imports/postprocessing_test.exs | Dawarich.JobsCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/imports/prepare_download_worker_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/imports/process_gpx_worker_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/imports/process_worker_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/imports/rails_blob_reference_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/imports/source_detector_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/imports/stale_recovery_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/imports/tcx_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/imports/teslamate_client_test.exs | ExUnit.Case | no | Client talks to listeners it opens on port 0 and owns; no database, env or global state |
| dawarich/imports/teslamate_sync_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/imports/trek_sync_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/imports/trek_worker_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/imports/ui_records_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/imports/upload_create_test.exs | Dawarich.JobsCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/imports/uploads_test.exs | Dawarich.JobsCase | yes | Writes files or shared build/output state; isolation not proven |
| dawarich/imports/watcher_test.exs | Dawarich.JobsCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/imports/zip_fanout_test.exs | Dawarich.JobsCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/ingest/friends_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich/ingest/intake_test.exs | Dawarich.IngestCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/ingest/sources_repo_test.exs | Dawarich.IngestCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/ingest_case_isolation_test.exs | Dawarich.IngestCase | no | Proves IngestCase async isolation: no shared sandbox owner and no table locks from setup |
| dawarich/insights/country_codes_test.exs | ExUnit.Case | yes | Redis/cache helpers may use shared keys; namespacing not proven |
| dawarich/insights_details_db_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/insights_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/integrations/sync_scheduling_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/integrations_test.exs | ExUnit.Case | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich/jobs/a12d2_corpus_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/jobs/a12rel_corpus_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/jobs/recalculation_entries_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/jobs/recalculation_lifecycle_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/jobs/release_adapters_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/jobs/residual_entries_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/jobs/wave2_contract_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/jsonb_test.exs | Dawarich.IngestCase | no | Reviewed same-process queries/DML or timezone parsing; transaction-local fixtures and no shared-state mutation |
| dawarich/lite/archival_warning_worker_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/local_time_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/locations_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich/mail/account_destroy_confirmation_worker_test.exs | Dawarich.JobsCase | yes | Exercises real queue services or scheduling |
| dawarich/mail/archival_approaching_worker_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/mail/delivery_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/mail/devise_residual_test.exs | Dawarich.JobsCase | yes | Exercises real queue services or scheduling |
| dawarich/mail/digests/data_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/mail/digests/delivery_worker_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/mail/digests/enqueue_test.exs | Dawarich.JobsCase | yes | Exercises real queue services or scheduling |
| dawarich/mail/digests/render_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/mail/family_invitation_worker_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/mail/location_request_worker_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/mail/oauth_account_link_worker_test.exs | Dawarich.JobsCase | yes | Exercises real queue services or scheduling |
| dawarich/mail/residual_commands_test.exs | Dawarich.JobsCase, Dawarich.IngestCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/mail/test_email_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/mail/wave2_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/map_api/reads_test.exs | Dawarich.IngestCase | no | Reviewed same-process queries/DML or timezone parsing; transaction-local fixtures and no shared-state mutation |
| dawarich/map_gallery_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/map_page_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/map_window_test.exs | ExUnit.Case | no | Reviewed same-process queries/DML or timezone parsing; transaction-local fixtures and no shared-state mutation |
| dawarich/native_lifecycle_test.exs | Dawarich.DataCase | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/navbar_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/notes_api/read_test.exs | Dawarich.IngestCase | no | Same-process sandbox queries; group :notes_fixture_ids serializes it with write_test, which inserts the same fixed ids |
| dawarich/notes_api/write_test.exs | Dawarich.IngestCase | no | IngestCase async path (private sandbox, no shared mode, no per-test DDL); telemetry handler filters by test pid; group :notes_fixture_ids serializes it with read_test, which uses the same fixed ids |
| dawarich/photos/provider_inventory_test.exs | ExUnit.Case | no | Client talks to listeners it opens on port 0 and owns; no database, env or global state |
| dawarich/photos/thumbnail_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/place_drawer_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/place_list_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/places/bulk_name_fetch_worker_test.exs | Dawarich.JobsCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/places/job_commands_test.exs | Dawarich.JobsCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/places/name_fetcher_test.exs | Dawarich.GeocodingCase | yes | Mutates shared persistent terms or ETS caches |
| dawarich/places/orphan_cleanup_worker_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/places/orphans_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/places/web_delete_test.exs | Dawarich.IngestCase | yes | Shared sandbox or ingestion helpers may reach other processes/global sources; conservatively retain |
| dawarich/places/web_write_test.exs | Dawarich.IngestCase | yes | Shared sandbox or ingestion helpers may reach other processes/global sources; conservatively retain |
| dawarich/point_exports_direct_worker_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/point_exports_fence_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/point_exports_test.exs | Dawarich.IngestCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/point_list_test.exs | ExUnit.Case | no | Reviewed same-process queries/DML or timezone parsing; transaction-local fixtures and no shared-state mutation |
| dawarich/points/anomaly_backfill_rebuild_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/points/anomaly_backfill_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/points/anomaly_filter_effects_test.exs | Dawarich.JobsCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/points/anomaly_filter_oracle_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/points/anomaly_filter_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/points/device_tag_backfill_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/points/records_device_tags_test.exs | Dawarich.JobsCase | no | Same-process parsing and timezone queries; writable temporary file has a per-test UUID |
| dawarich/points/tracker_backfill_test.exs | Dawarich.JobsCase | no | Reviewed same-process queries/DML or timezone parsing; transaction-local fixtures and no shared-state mutation |
| dawarich/points/web_destroy_test.exs | Dawarich.IngestCase | no | Reviewed same-process queries/DML or timezone parsing; transaction-local fixtures and no shared-state mutation |
| dawarich/posters/command_test.exs | Dawarich.IngestCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/posters/create_worker_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/posters/generation_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/posters/native_renderer_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/posters/persistence_test.exs | Dawarich.IngestCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/posters/publication_test.exs | Dawarich.JobsCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/posters/track_builder_test.exs | Dawarich.IngestCase | no | Reviewed same-process queries/DML or timezone parsing; transaction-local fixtures and no shared-state mutation |
| dawarich/qr_cache_test.exs | ExUnit.Case | yes | Mutates shared persistent terms or ETS caches |
| dawarich/rails_counter_store_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/rails_effects_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/rails_time_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/raw_data/archives_destroy_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/raw_data/clearer_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/raw_data/restorer_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/redis_test.exs | ExUnit.Case | yes | Redis/cache helpers may use shared keys; namespacing not proven |
| dawarich/registration_setting_migration_test.exs | Dawarich.ScratchCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/release_cloud_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/release_jobs_test.exs | Dawarich.JobsCase, Dawarich.ScratchCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/release_migration_test.exs | Dawarich.ScratchCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/release_migrations/effects/copy_registration_setting_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/release_operations/achievements_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/release_operations/anomalies_test.exs | Dawarich.JobsCase | yes | Exercises real queue services or scheduling |
| dawarich/release_operations/anomalies_user_test.exs | Dawarich.JobsCase | yes | Exercises real queue services or scheduling |
| dawarich/release_operations/anomaly_claims_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/release_operations/import_backfill_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/release_operations/per_tracker_test.exs | Dawarich.JobsCase | yes | Exercises real queue services or scheduling |
| dawarich/release_operations/recalculation_zone_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/release_registration_copy_test.exs | ExUnit.Case | yes | Changes schemas, sequences, or database configuration |
| dawarich/release_test.exs | ExUnit.Case | yes | Changes schemas, sequences, or database configuration |
| dawarich/residency_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich/route_videos/purge_worker_test.exs | Dawarich.JobsCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/route_videos/retention_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/route_videos/writes_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/runtime_config_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/share_management/mutations_test.exs | Dawarich.IngestCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/share_management/params_test.exs | ExUnit.Case | no | Reviewed same-process queries/DML or timezone parsing; transaction-local fixtures and no shared-state mutation |
| dawarich/share_management/read_test.exs | ExUnit.Case | no | Same-process sandbox queries; bounded fixture keys are converted to atoms without depending on another test loading them |
| dawarich/shared_api/live_test.exs | Dawarich.ApiEndpointCase | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich/shared_api/photos_test.exs | Dawarich.ApiEndpointCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/shared_api/points_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich/shared_api/trip_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/state_cursor_test.exs | Dawarich.JobsCase | yes | Redis/cache helpers may use shared keys; namespacing not proven |
| dawarich/state_primitives_migration_test.exs | Dawarich.ScratchCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/stats/bulk_calculator_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/stats/calculate_month_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/stats/full_recalculation_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/stats/geocoded_days_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/stats/hexagons_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/stats/insights_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich/stats/refresh_toponyms_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/stats/stats_jobs_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/stats/summary_test.exs | Dawarich.IngestCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/stats/toponyms_refresh_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/stats/tracked_months_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/stats_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/stats_work_state_migration_test.exs | Dawarich.ScratchCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/storage/blobs_test.exs | Dawarich.IngestCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/subscription_token_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/sync1153_sharing_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich/tag_pages_test.exs | ExUnit.Case | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich/tags/validation_test.exs | Dawarich.IngestCase | no | Reviewed same-process queries/DML or timezone parsing; transaction-local fixtures and no shared-state mutation |
| dawarich/tags/writes_test.exs | Dawarich.IngestCase | no | Reviewed same-process queries/DML or timezone parsing; transaction-local fixtures and no shared-state mutation |
| dawarich/test_seed_ids_test.exs | Dawarich.DataCase | no | Uses a connection-local temporary table and sequence |
| dawarich/time_zone_options_test.exs | ExUnit.Case | yes | Mutates shared persistent terms or ETS caches |
| dawarich/timeline/day_rows_test.exs | Dawarich.JobsCase | no | Reviewed fixture DML and test-process queries; telemetry handler is unique and filters by caller PID |
| dawarich/timeline/days_test.exs | Dawarich.JobsCase | no | Fixtures and queries use sandbox Repo in the test process; scratch reset is unnecessary |
| dawarich/timeline/month_summary_test.exs | Dawarich.JobsCase | no | Fixtures and queries use sandbox Repo in the test process; scratch reset is unnecessary |
| dawarich/track_segment_page_test.exs | ExUnit.Case | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich/tracks/backfill_commands_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/tracks/backfill_schema_test.exs | Dawarich.ScratchCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/tracks/daily_worker_test.exs | Dawarich.TracksCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/tracks/fixtures_test.exs | ExUnit.Case | yes | Changes schemas, sequences, or database configuration |
| dawarich/tracks/import_reprocessor_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/tracks/segment_editor_test.exs | Dawarich.IngestCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/trial/welcome_claim_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/trial/welcome_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/trip_corpus_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/trip_days_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/trip_gate_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/trip_list_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich/trip_page_test.exs | ExUnit.Case | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich/trips/plan_read_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich/trips/web_delete_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich/trips/web_params_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich/trips/web_write_test.exs | Dawarich.IngestCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/ttl_cache_test.exs | ExUnit.Case | yes | Mutates shared persistent terms or ETS caches |
| dawarich/user_data/archive_test.exs | ExUnit.Case | no | Pure parsing over ExUnit tmp_dir files; no database, env or global state |
| dawarich/user_data/export_entities_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/user_data/export_files_test.exs | Dawarich.JobsCase | yes | Uses Rails parity or an external process/peer |
| dawarich/user_data/export_monthly_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/user_data/export_worker_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/user_data/fixtures_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/user_data/import_worker_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/user_data/restore_entities_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/user_data/restore_files_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/user_data/restore_monthly_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/user_data/restore_parser_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/user_data/restore_places_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/user_data/restore_points_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/user_data/restore_raw_archives_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/user_data/restore_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/user_time_zone_iana_test.exs | Dawarich.JobsCase | no | Reviewed same-process queries/DML or timezone parsing; transaction-local fixtures and no shared-state mutation |
| dawarich/user_time_zone_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich/users/recalculate_worker_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/users/recalculation_args_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/users/recalculation_corpus_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/users/recalculation_digests_test.exs | Dawarich.JobsCase | yes | Exercises real queue services or scheduling |
| dawarich/users/recalculation_period_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/users/recalculation_stats_test.exs | Dawarich.JobsCase | yes | Exercises real queue services or scheduling |
| dawarich/users/recalculation_tracks_test.exs | Dawarich.JobsCase | yes | Exercises ownership flags; retain conservatively for other-process readers |
| dawarich/visits/calendar_test.exs | Dawarich.VisitsCase | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich/visits/detection_test.exs | Dawarich.VisitsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/visits/persister_test.exs | Dawarich.VisitsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/visits/redetect_worker_test.exs | Dawarich.VisitsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/visits/stages_test.exs | Dawarich.VisitsCase | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich/visits/suggest_worker_test.exs | Dawarich.VisitsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/visits/web_bulk_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/visits/web_delete_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/visits/web_merge_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich/visits/web_scope_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich/visits/web_settings_test.exs | Dawarich.IngestCase | yes | Shared sandbox or ingestion helpers may reach other processes/global sources; conservatively retain |
| dawarich/visits/web_update_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/visits_api/batch_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/visits_api/create_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich/visits_api/merge_bulk_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/visits_api/read_test.exs | Dawarich.IngestCase | no | Reviewed same-process queries/DML or timezone parsing; transaction-local fixtures and no shared-state mutation |
| dawarich/visits_api/select_place_test.exs | Dawarich.JobsCase | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich/visits_api/update_test.exs | Dawarich.JobsCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich/wave5b_fixtures_test.exs | ExUnit.Case | yes | Changes schemas, sequences, or database configuration |
| dawarich_web/a10b_ownership_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/a10c_ownership_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/a10c_routes_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/a12f3b_i04_test.exs | Dawarich.DataCase | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich_web/a12f3b_s01_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich_web/a12f3b_s05_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich_web/a8_gate_endpoint_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/a8_remaining_parity_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/a8_remaining_request_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/a8_request_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/a8_routes_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich_web/a8_videos_visits_parity_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/achievement_actions_request_test.exs | ExUnit.Case | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich_web/achievement_public_test.exs | ExUnit.Case | yes | Mutates shared persistent terms or ETS caches |
| dawarich_web/achievement_sharing_test.exs | ExUnit.Case | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich_web/achievement_unlock_reveal_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich_web/achievement_unlocks_test.exs | ExUnit.Case | yes | Exercises PostgreSQL locking, notification, or cross-connection behavior |
| dawarich_web/achievements_gate_endpoint_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/achievements_live_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/achievements_parity_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/active_storage_test.exs | Dawarich.IngestCase | yes | Changes schemas, sequences, or database configuration |
| dawarich_web/admin_gate_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/admin_live_auth_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/admin_mutations_test.exs | ExUnit.Case | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich_web/admin_pages_parity_test.exs | Dawarich.JobsCase | yes | Changes schemas, sequences, or database configuration |
| dawarich_web/admin_setting_writes_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich_web/admin_users_parity_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich_web/admin_writes_request_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich_web/api/account_endpoint_test.exs | Dawarich.ApiEndpointCase, Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/account_golden_test.exs | Dawarich.ApiEndpointCase, Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/auth_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/body_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/family_golden_test.exs | Dawarich.ApiEndpointCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/family_writes_golden_test.exs | Dawarich.ApiEndpointCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/ingest_controller_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/ingest_endpoint_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/ingest_golden_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/locations_photos_endpoint_test.exs | Dawarich.ApiEndpointCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/locations_photos_golden_test.exs | Dawarich.ApiEndpointCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/map_endpoint_test.exs | Dawarich.ApiEndpointCase | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich_web/api/map_golden_test.exs | Dawarich.ApiEndpointCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/notes_endpoint_test.exs | Dawarich.ApiEndpointCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/notes_golden_test.exs | Dawarich.ApiEndpointCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/places_golden_test.exs | Dawarich.ApiEndpointCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/plan_endpoint_test.exs | Dawarich.ApiEndpointCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/plan_golden_test.exs | Dawarich.ApiEndpointCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/remaining_routes_test.exs | Dawarich.ApiEndpointCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/respond_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich_web/api/shared_endpoint_test.exs | Dawarich.ApiEndpointCase, Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/shared_golden_test.exs | Dawarich.ApiEndpointCase, Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/stats_endpoint_test.exs | Dawarich.ApiEndpointCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/stats_golden_test.exs | Dawarich.ApiEndpointCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/two_factor_endpoint_test.exs | Dawarich.ApiEndpointCase, Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/visits_endpoint_test.exs | Dawarich.ApiEndpointCase, Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/api/visits_golden_test.exs | Dawarich.ApiEndpointCase, Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/auth_account/http_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/auth_account/response_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/auth_account_link/http_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/auth_account_link/response_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/auth_api/http_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/auth_api/response_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich_web/auth_api_keys/http_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/auth_common_pipeline_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/auth_gate_endpoint_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/auth_gate_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/auth_otp/http_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/auth_otp/response_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/auth_recovery_activation_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/auth_two_factor/form_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich_web/auth_two_factor/http_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/auth_two_factor/response_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/background_jobs_live_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/cable_pg_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/cable_replay_test.exs | Dawarich.IngestCase | yes | Shared sandbox or ingestion helpers may reach other processes/global sources; conservatively retain |
| dawarich_web/cable_route_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/cable_test.exs | Dawarich.IngestCase | yes | Redis/cache helpers may use shared keys; namespacing not proven |
| dawarich_web/digests_live_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/endpoint_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/exports_create_test.exs | Dawarich.IngestCase | yes | Uses Rails parity or an external process/peer |
| dawarich_web/exports_delete_test.exs | Dawarich.IngestCase | yes | Uses Rails parity or an external process/peer |
| dawarich_web/exports_live_test.exs | ExUnit.Case | yes | Shared sandbox or ingestion helpers may reach other processes/global sources; conservatively retain |
| dawarich_web/family_invitation_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/family_locations_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/family_pages_parity_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/family_pages_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/family_session_handback_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/home_gate_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/host_authorization_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/icon_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/imports_download_pipeline_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/imports_download_socket_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/imports_download_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/imports_exports_parity_test.exs | ExUnit.Case | yes | Shared sandbox or ingestion helpers may reach other processes/global sources; conservatively retain |
| dawarich_web/imports_extraction_navigation_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich_web/imports_live_test.exs | ExUnit.Case | yes | Shared sandbox or ingestion helpers may reach other processes/global sources; conservatively retain |
| dawarich_web/imports_native_pages_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/imports_pages_parity_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/imports_remaining_pages_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/imports_upload_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/insights_details_parity_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/insights_endpoint_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/insights_home_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/insights_live_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/layout_parity_test.exs | ExUnit.Case, Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/live_socket_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/map_data_frames_test.exs | Dawarich.JobsCase | yes | Uses Rails parity or an external process/peer |
| dawarich_web/map_data_handback_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/map_data_parity_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/map_frames_endpoint_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/map_frames_parity_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/map_frames_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/map_live_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/map_parity_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/map_write_request_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/map_write_routes_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/map_writes_handback_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/map_writes_parity_test.exs | Dawarich.JobsCase | yes | Uses Rails parity or an external process/peer |
| dawarich_web/notifications_live_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/notifications_parity_test.exs | ExUnit.Case | yes | Shared sandbox or ingestion helpers may reach other processes/global sources; conservatively retain |
| dawarich_web/onboarding_modal_test.exs | ExUnit.Case | yes | Shared sandbox or ingestion helpers may reach other processes/global sources; conservatively retain |
| dawarich_web/place_actions_test.exs | Dawarich.IngestCase | yes | Uses Rails parity or an external process/peer |
| dawarich_web/place_navigation_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/places_gate_endpoint_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/places_live_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich_web/places_parity_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/point_exports_direct_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/point_exports_parity_test.exs | Dawarich.IngestCase | yes | Uses Rails parity or an external process/peer |
| dawarich_web/point_list_actions_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/points_live_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich_web/posters_endpoint_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/posters_parity_test.exs | Dawarich.IngestCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich_web/public_files_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/public_home_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/rails_auth_test.exs | ExUnit.Case | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich_web/rails_form_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich_web/rails_page_test.exs | ExUnit.Case | yes | Shared sandbox or ingestion helpers may reach other processes/global sources; conservatively retain |
| dawarich_web/rails_session_identity_test.exs | ExUnit.Case | no | Own sandbox checkout (or no database); same-process queries and transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes, DDL or real commits |
| dawarich_web/rails_session_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/rate_limit_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/residual_mail_ownership_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/route_video_actions_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/segment_actions_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/settings_live_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/settings_parity_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/share_management_endpoint_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/share_management_page_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/share_management_parity_test.exs | Dawarich.IngestCase | yes | Starts another process; DB visibility or helper ownership is uncertain, retain conservatively |
| dawarich_web/sharing_endpoint_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/sharing_parity_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich_web/stats_format_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/stats_live_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/stats_parity_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/storage_routes_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/strangler_test.exs | ExUnit.Case | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich_web/tag_actions_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/tags_live_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich_web/test_email_test.exs | ExUnit.Case | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich_web/trial_live_auth_test.exs | ExUnit.Case | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
| dawarich_web/trial_resume_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/trial_upgrade_test.exs | ExUnit.Case | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/trial_welcome_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/trip_export_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/trip_form_navigation_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich_web/trip_forms_actions_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/trip_itinerary_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich_web/trip_missing_data_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/trip_note_actions_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/trip_plan_hosts_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/trips_gate_endpoint_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/trips_index_parity_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/trips_live_test.exs | Dawarich.JobsCase | yes | Scratch repo/helper behavior not fully proven safe for sandbox; conservatively retain |
| dawarich_web/trips_show_parity_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/user_data_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/visit_actions_test.exs | Dawarich.JobsCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/visit_settings_actions_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| dawarich_web/visit_settings_live_test.exs | Dawarich.IngestCase | yes | Shared sandbox or ingestion helpers may reach other processes/global sources; conservatively retain |
| dawarich_web/visits_navigation_test.exs | Dawarich.IngestCase | no | IngestCase async path: private sandbox owner without shared mode and no per-test DDL; transaction-local fixtures; no env, Redis, telemetry, ETS/persistent_term writes or real commits |
| dawarich_web/web_form_params_test.exs | Dawarich.IngestCase | yes | Changes application configuration or system environment shared by other processes |
| mix/tasks/dawarich.build_inputs_test.exs | ExUnit.Case | yes | Case and transitive helpers have not been proven free of global state; conservatively retain |
