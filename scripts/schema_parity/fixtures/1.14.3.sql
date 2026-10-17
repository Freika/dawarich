ALTER TABLE "stats" ADD "calculation_version" integer DEFAULT 0 NOT NULL;
ALTER TABLE "users" ADD "stats_swept_at" timestamp(6);
ALTER TABLE "stats" ADD "repair_deferred_at" timestamp(6);
