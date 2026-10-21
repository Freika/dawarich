ALTER TABLE "users" ADD "first_name" character varying;
ALTER TABLE "users" ADD "last_name" character varying;
ALTER TABLE "visits" ADD "confidence" smallint;
ALTER TABLE "visits" ADD "confidence_breakdown" jsonb DEFAULT '{}' NOT NULL;
ALTER TABLE "users" ADD "changelog_consent" integer;
