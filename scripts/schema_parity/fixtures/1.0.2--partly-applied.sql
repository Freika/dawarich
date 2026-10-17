ALTER TABLE "digests" ADD "month" integer;
DROP INDEX "index_digests_on_user_id_and_year_and_period_type";
ALTER TABLE "tracks" ADD "dominant_mode" integer DEFAULT 0;
ALTER TABLE "digests" ADD "travel_patterns" jsonb DEFAULT '{}';
