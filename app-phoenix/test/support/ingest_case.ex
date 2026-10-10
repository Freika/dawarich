defmodule Dawarich.IngestCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Dawarich.Repo

  @sql Path.expand("../../priv/repo/sql/20260928130000_rails_commands.sql", __DIR__)
  @owners Path.expand("../../priv/repo/sql/20260927120100_job_control.sql", __DIR__)
  @external_resource @sql
  @external_resource @owners
  @control_relations Regex.scan(
                       ~r/IF NOT EXISTS (?:phoenix\.)?(\w+)/,
                       File.read!(@sql) <> File.read!(@owners),
                       capture: :all_but_first
                     )
                     |> List.flatten()

  using do
    quote do
      alias Dawarich.Repo
      import Dawarich.IngestCase
    end
  end

  setup context do
    if context[:async] && (context[:account_link_committed] || context[:map_matching_tasks]),
      do: raise(ArgumentError, "committed or shared-owner IngestCase tests cannot be async")

    unless context[:account_link_committed] do
      if context[:map_matching_tasks] do
        owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)

        on_exit(fn ->
          try do
            Dawarich.MapMatchingTasks.await!()
          after
            Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
          end
        end)
      else
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
        unless context[:async], do: Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      end
    end

    unless context[:api_public_only] || control_tables_present?() do
      Repo.query!("CREATE SCHEMA IF NOT EXISTS phoenix")
      Repo.query!(File.read!(@sql), [], query_type: :text)
      Repo.query!(File.read!(@owners), [], query_type: :text)
    end

    Dawarich.Ingest.Sources.forget()
    :ok
  end

  defp control_tables_present? do
    [[count]] =
      Repo.query!(
        "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'phoenix' AND c.relname = ANY($1)",
        [@control_relations],
        log: false
      ).rows

    count == length(@control_relations)
  end

  def user!(attrs \\ %{}) do
    stamp = NaiveDateTime.utc_now()

    row =
      Map.merge(
        %{
          email: "a3-#{System.unique_integer([:positive])}@dawarich.test",
          api_key: "",
          status: 1,
          active_until: nil,
          deleted_at: nil,
          created_at: stamp,
          updated_at: stamp
        },
        attrs
      )

    {1, [%{id: id}]} = Dawarich.Test.SeedIds.insert_all!(Repo, "users", [row], returning: [:id])
    id
  end

  def commands,
    do: Repo.query!("SELECT kind, payload FROM phoenix.rails_commands ORDER BY id").rows
end
