defmodule Dawarich.IngestCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Dawarich.Repo

  @sql Path.expand("../../priv/repo/sql/20260928130000_rails_commands.sql", __DIR__)
  @owners Path.expand("../../priv/repo/sql/20260927120100_job_control.sql", __DIR__)

  using do
    quote do
      alias Dawarich.Repo
      import Dawarich.IngestCase
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    Repo.query!("CREATE SCHEMA IF NOT EXISTS phoenix")
    Repo.query!(File.read!(@sql), [], query_type: :text)
    Repo.query!(File.read!(@owners), [], query_type: :text)
    Dawarich.Ingest.Sources.forget()
    :ok
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

    {1, [%{id: id}]} = Repo.insert_all("users", [row], returning: [:id])
    id
  end

  def commands,
    do: Repo.query!("SELECT kind, payload FROM phoenix.rails_commands ORDER BY id").rows
end
