defmodule Dawarich.ReleaseMigrations.V1_7_0 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.7.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260420190307", &add_subscription_source_and_signup_variant_to_users/1},
      {"20260420211352", &create_flipper_tables/1},
      {"20260421200002", &add_partial_index_on_users_signup_variant_reverse_trial/1,
       transaction: false},
      {"20260421230359", &add_concurrent_indexes_for_subscription_lookup/1, transaction: false},
      {"20260426204917", &drop_unused_subscription_source_index/1, transaction: false}
    ]
  end

  defp add_subscription_source_and_signup_variant_to_users(repo) do
    unless column?(repo, "users", "subscription_source") do
      sql!(repo, ~S|ALTER TABLE "users" ADD "subscription_source" integer DEFAULT 0 NOT NULL;|)
    end

    unless column?(repo, "users", "signup_variant") do
      sql!(repo, ~S|ALTER TABLE "users" ADD "signup_variant" character varying;|)
    end
  end

  defp create_flipper_tables(repo) do
    unless table?(repo, "flipper_features") do
      sql!(
        repo,
        ~S|CREATE TABLE "flipper_features" ("id" bigserial primary key, "key" character varying NOT NULL, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL);|
      )
    end

    unless index_name?(repo, "flipper_features", "index_flipper_features_on_key") do
      sql!(
        repo,
        ~S|CREATE UNIQUE INDEX "index_flipper_features_on_key" ON "flipper_features" ("key");|
      )
    end

    unless table?(repo, "flipper_gates") do
      sql!(
        repo,
        ~S|CREATE TABLE "flipper_gates" ("id" bigserial primary key, "feature_key" character varying NOT NULL, "key" character varying NOT NULL, "value" text, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL);|
      )
    end

    unless index_name?(
             repo,
             "flipper_gates",
             "index_flipper_gates_on_feature_key_and_key_and_value"
           ) do
      sql!(
        repo,
        ~S|CREATE UNIQUE INDEX "index_flipper_gates_on_feature_key_and_key_and_value" ON "flipper_gates" ("feature_key", "key", "value");|
      )
    end
  end

  defp add_partial_index_on_users_signup_variant_reverse_trial(repo) do
    unless index_name?(repo, "users", "index_users_on_signup_variant_reverse_trial") do
      sql!(
        repo,
        ~S|CREATE INDEX CONCURRENTLY "index_users_on_signup_variant_reverse_trial" ON "users" ("signup_variant") WHERE signup_variant = 'reverse_trial';|
      )
    end
  end

  defp add_concurrent_indexes_for_subscription_lookup(repo) do
    unless index_name?(repo, "users", "index_users_on_subscription_source") do
      sql!(
        repo,
        ~S|CREATE INDEX CONCURRENTLY "index_users_on_subscription_source" ON "users" ("subscription_source");|
      )
    end
  end

  defp drop_unused_subscription_source_index(repo) do
    if index_name?(repo, "users", "index_users_on_subscription_source") do
      sql!(repo, ~S|DROP INDEX CONCURRENTLY "index_users_on_subscription_source";|)
    end
  end
end
