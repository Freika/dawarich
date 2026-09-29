defmodule Dawarich.RuntimeConfigTest do
  use ExUnit.Case, async: false

  @runtime Path.expand("../../config/runtime.exs", __DIR__)
  @vars ~w(HOSTNAME DATABASE_URL DATABASE_HOST DATABASE_NAME PGSSLMODE PGSSLROOTCERT DAWARICH_RAILS_ARGS REDIS_URL RAILS_JOB_QUEUE_DB)

  setup do
    saved = Map.new(@vars, &{&1, System.get_env(&1)})
    Enum.each(@vars, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(saved, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)
  end

  defp prod(env \\ %{}) do
    Enum.each(env, fn {name, value} -> System.put_env(name, value) end)
    config = Config.Reader.read!(@runtime, env: :prod)[:dawarich]
    {config[Dawarich.Repo], config[Oban]}
  end

  defp redis(env) do
    Enum.each(env, fn {name, value} -> System.put_env(name, value) end)
    Config.Reader.read!(@runtime, env: :prod)[:dawarich][:redis]
  end

  test "sizes the pool from the queue limits and enables Oban's services" do
    {repo, oban} = prod()

    assert oban[:queues] == [
             app_version_checking: 1,
             mailers: 2,
             trips: 2,
             maintenance: 1,
             exports: 1,
             projections: 1,
             imports: 1
           ]

    assert repo[:pool_size] == 12
    assert oban[:peer] == Oban.Peers.Database
    assert oban[:stager] == {Oban.Stager, []}
    assert oban[:pruner] == [max_age: {1, :day}]
    assert oban[:lifeline] == [rescue_after: {60, :minute}]
    assert oban[:shutdown_grace_period] == 12_000
  end

  test "wave-4 workers run on a configured queue and time out before Lifeline" do
    {_repo, oban} = prod()

    for worker <- [
          Dawarich.Imports.UpdatePointsCountWorker,
          Dawarich.AirTrail.ImportFlightsWorker
        ] do
      assert Keyword.has_key?(oban[:queues], worker.__opts__()[:queue])
      assert worker.timeout(%Oban.Job{}) < :timer.minutes(60)
    end
  end

  test "falls back to the host name when HOSTNAME is missing or not a single word" do
    {:ok, host} = :inet.gethostname()

    assert {_, oban} = prod()
    assert oban[:node] == to_string(host)

    assert {_, oban} = prod(%{"HOSTNAME" => "has space"})
    assert oban[:node] == to_string(host)
  end

  test "keeps Rails' database name fallback" do
    assert {repo, _} = prod()
    assert repo[:database] == "dawarich_production"
  end

  test "maps libpq's require, verify-* and disable sslmodes, preferring the URL's to PGSSLMODE" do
    assert {repo, _} = prod(%{"PGSSLMODE" => "require"})
    assert repo[:ssl] == [verify: :verify_none]

    System.delete_env("PGSSLMODE")

    assert {repo, _} =
             prod(%{
               "DATABASE_URL" => "postgis://u:p@db.example:6432/dawarich?sslmode=verify-full"
             })

    assert repo[:ssl] == true
    refute repo[:url] =~ "sslmode"

    assert {repo, _} = prod(%{"PGSSLMODE" => "disable"})
    assert repo[:ssl] == true

    System.delete_env("DATABASE_URL")
    assert {repo, _} = prod(%{"PGSSLMODE" => "disable"})
    assert repo[:ssl] == false

    assert {repo, _} =
             prod(%{"PGSSLMODE" => "verify-ca", "PGSSLROOTCERT" => "/etc/ssl/db-root.crt"})

    assert repo[:ssl] == [cacertfile: "/etc/ssl/db-root.crt"]
  end

  test "Redis uses Sidekiq's database" do
    assert redis(%{"REDIS_URL" => "redis://r:6379"}) == [url: "redis://r:6379", database: 1]

    assert redis(%{"REDIS_URL" => "redis://r:6379", "RAILS_JOB_QUEUE_DB" => "4"}) ==
             [url: "redis://r:6379", database: 4]
  end

  test "connects over IPv6 when the database host has no IPv4 address" do
    assert {repo, _} = prod(%{"DATABASE_HOST" => "::1"})
    assert repo[:socket_options] == [:inet6]

    System.put_env("DATABASE_HOST", "127.0.0.1")
    assert {repo, _} = prod()
    assert repo[:socket_options] == []

    assert {repo, _} = prod(%{"DATABASE_URL" => "postgres://u:p@[::1]:5432/dawarich"})
    assert repo[:socket_options] == [:inet6]
  end
end
