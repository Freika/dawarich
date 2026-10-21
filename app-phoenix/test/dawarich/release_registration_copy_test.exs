defmodule Dawarich.ReleaseRegistrationCopyTest do
  use ExUnit.Case, async: false

  alias Dawarich.{Release, Repo, SchemaFingerprint}

  @fixture Path.expand("../fixtures/auth/activation.json", __DIR__)
  @version 20_261_004_170_000

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Dawarich.MigrationModules.purge()
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    assert :ok = Release.migrate(command: fn _ -> {:ok, nil} end, env: %{})
    Repo.query!("DELETE FROM phoenix.registration_setting", [], log: false)
    {:ok, previous} = Dawarich.Redis.cache_command(["GET", "dawarich/registration_enabled"])

    on_exit(fn ->
      config = Application.fetch_env!(:dawarich, :redis)

      opts =
        Dawarich.Redis.options(config[:url], config[:cache_database]) |> Keyword.delete(:name)

      {:ok, conn} = Redix.start_link(config[:url], opts)

      try do
        if previous do
          Redix.command(conn, ["SET", "dawarich/registration_enabled", previous])
        else
          Redix.command(conn, ["DEL", "dawarich/registration_enabled"])
        end
      after
        Redix.stop(conn)
      end

      Release.migrate(command: fn _ -> {:ok, nil} end, env: %{})
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    end)

    :ok
  end

  test "Release migrate copies registration after phoenix schema upgrade without public DDL" do
    baseline = SchemaFingerprint.public()
    ledger = Repo.query!("SELECT version FROM public.schema_migrations ORDER BY version").rows
    Repo.query!("ALTER TABLE phoenix.registration_setting ALTER COLUMN enabled SET NOT NULL")
    Repo.query!("DELETE FROM phoenix.phoenix_schema_migrations WHERE version=$1", [@version])

    bytes =
      fixture()["registration_legacy"]["marshal_7_0_uncompressed"]["nil"] |> Base.decode64!()

    assert {:ok, "OK"} =
             Dawarich.Redis.cache_command(["SET", "dawarich/registration_enabled", bytes])

    assert :ok = Release.migrate()
    assert Repo.query!("SELECT enabled FROM phoenix.registration_setting").rows == [[nil]]
    assert SchemaFingerprint.public() == baseline

    assert Repo.query!("SELECT version FROM public.schema_migrations ORDER BY version").rows ==
             ledger
  end

  test "migration rerun with stored nil works without Redis and failed first copy is reported" do
    source = fixture()["registration"]["nil"] |> Base.decode64!()
    assert :ok = Release.migrate(command: fn _ -> {:ok, source} end)
    assert :ok = Release.migrate(command: fn _ -> flunk("completed copy must not read Redis") end)
    assert Repo.query!("SELECT enabled FROM phoenix.registration_setting").rows == [[nil]]
    Repo.query!("DELETE FROM phoenix.registration_setting", [], log: false)

    assert_raise RuntimeError, "registration copy refused", fn ->
      Release.migrate(command: fn _ -> {:error, :disconnected} end)
    end

    assert Repo.query!("SELECT enabled FROM phoenix.registration_setting").rows == []
  end

  defp fixture, do: @fixture |> File.read!() |> Jason.decode!()
end
