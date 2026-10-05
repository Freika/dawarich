defmodule Dawarich.CLI.Migrate do
  @moduledoc false

  import Dawarich.CLI, only: [puts: 2, fail: 2]

  alias Dawarich.{Release, ReleaseMigrator}
  alias Dawarich.Release.Lifecycle

  @last_rails_release "1.15.3"

  def migrate([], ctx) do
    :ok = Release.migrate(release_opts(ctx))

    message =
      if Lifecycle.mode(ctx.env) == {:ok, :native},
        do: "public, phoenix and oban schemas: current",
        else: "phoenix and oban schemas: current"

    puts(ctx, message)
    0
  end

  def migrate(_args, ctx), do: fail(ctx, "usage: dawarich migrate [status]")

  def native_migrate(args, ctx) do
    case Lifecycle.mode(ctx.env) do
      {:ok, :native} -> migrate(args, ctx)
      {:ok, :rails} -> fail(ctx, describe(:lifecycle_disabled))
      {:error, reason} -> fail(ctx, describe(reason))
    end
  end

  def release_opts(ctx), do: Enum.to_list(Map.take(ctx, [:repo, :env]))

  def status([], ctx) do
    case Release.readiness() do
      :no_connection ->
        puts(ctx, schemas(:no_connection))
        1

      readiness ->
        public = ReleaseMigrator.status(ctx.repo)
        Enum.each([schemas(readiness) | public_lines(public)], &puts(ctx, &1))
        if match?({:error, _}, public), do: 1, else: 0
    end
  end

  def status(_args, ctx), do: fail(ctx, "usage: dawarich migrate status")

  defp schemas(:ready), do: "phoenix and oban schemas: current"

  defp schemas(:schemas_behind),
    do: "phoenix and oban schemas: behind this image; run dawarich migrate"

  defp schemas(:no_connection), do: "phoenix and oban schemas: the database did not answer"

  defp public_lines({:ok, :current}), do: ["public schema: current"]

  defp public_lines({:ok, :fresh}),
    do: ["public schema: empty; the baseline schema will be loaded"]

  defp public_lines({:ok, {:pending, steps}}) do
    noun = if length(steps) == 1, do: "version", else: "versions"

    [
      "public schema: #{length(steps)} pending #{noun}"
      | Enum.map(steps, fn {release, v} -> "  #{release} #{v}" end)
    ]
  end

  defp public_lines({:error, reason}), do: ["public schema: " <> describe(reason)]

  def describe({:unknown_release, release}), do: "no Ecto release module for #{release}"

  def describe({:failed, release, version, message}),
    do: "failed #{release} #{version}: #{String.replace(message, ~r/\s+/, " ")}"

  def describe({:newer, versions}),
    do: "refused: newer than this image (#{Enum.join(versions, " ")})"

  def describe({:below_floor, release}),
    do:
      "refused: this database has not reached Dawarich #{release}, and this image upgrades only from 1.0.0; " <>
        "start the Dawarich #{@last_rails_release} image once so Rails upgrades it, then start this image"

  def describe({:not_dawarich, count}),
    do:
      "refused: schema_migrations holds #{count} versions and none of them is a Dawarich migration; " <>
        "check DATABASE_NAME"

  def describe({:foreign_schema, schema, others}),
    do: "refused: Rails tables outside public (search path #{schema}; #{Enum.join(others, " ")})"

  def describe({:locked, holder}),
    do: "refused: another migrator holds the lease (#{holder})"

  def describe({:lease_lost, holder}), do: "refused: lease lost by #{holder}"
  def describe(:pool_too_small), do: "refused: the repo pool needs two connections"
  def describe({:timezone, value}), do: "refused: session time zone is #{value}, not UTC"

  def describe({:rails_migrating, pid}),
    do:
      "refused: a Rails migrator holds its advisory lock (backend #{pid}); stop it, or if no Rails process runs, " <>
        "wait for PgBouncer's server_lifetime or restart PgBouncer"

  def describe({:pending_data, _}),
    do:
      "refused: pending data migrations; run the last Rails image before enabling native lifecycle"

  def describe(:registration_copy_refused), do: "registration copy refused"

  def describe(:invalid_lifecycle_flag),
    do: "refused: DAWARICH_PHOENIX_LIFECYCLE must be true or false"

  def describe(:cloud_native_lifecycle), do: "refused: native lifecycle requires self-hosted mode"

  def describe(:migration_lock_busy),
    do: "refused: another migrator holds the database advisory lock"

  def describe(:lifecycle_disabled),
    do: "refused: native lifecycle is disabled; enable DAWARICH_PHOENIX_LIFECYCLE=true"

  def describe(:seeds_require_current),
    do: "refused: seeds require current public and private schemas; run dawarich migrate"

  def describe(error) when is_exception(error), do: "refused: #{Exception.message(error)}"
end
