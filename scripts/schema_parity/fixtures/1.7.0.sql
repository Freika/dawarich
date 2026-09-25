ALTER TABLE "users" ADD "subscription_source" integer DEFAULT 0 NOT NULL;
ALTER TABLE "users" ADD "signup_variant" character varying;
CREATE TABLE "flipper_features" ("id" bigserial primary key, "key" character varying NOT NULL, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL);
CREATE UNIQUE INDEX "index_flipper_features_on_key" ON "flipper_features" ("key");
CREATE TABLE "flipper_gates" ("id" bigserial primary key, "feature_key" character varying NOT NULL, "key" character varying NOT NULL, "value" text, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL);
CREATE UNIQUE INDEX "index_flipper_gates_on_feature_key_and_key_and_value" ON "flipper_gates" ("feature_key", "key", "value");
CREATE INDEX "index_users_on_signup_variant_reverse_trial" ON "users" ("signup_variant") WHERE signup_variant = 'reverse_trial';
CREATE INDEX "index_users_on_subscription_source" ON "users" ("subscription_source");
