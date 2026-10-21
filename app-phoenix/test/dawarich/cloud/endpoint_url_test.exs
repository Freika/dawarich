defmodule Dawarich.Cloud.EndpointURLTest do
  use ExUnit.Case, async: true
  alias Dawarich.Cloud.{EndpointURL, SessionConnection}
  alias Dawarich.Release.Lifecycle

  defmodule ConfigRepo do
    def config, do: Process.get(:endpoint_repo_config, [])
    def query!(_, _, _), do: send(self(), :unexpected_endpoint_query)
  end

  test "B1-R2 mapped and compatible aliases refuse environment Repo and public calls before effects" do
    matrix = File.read!("test/fixtures/cloud_admission_matrix.json") |> Jason.decode!()

    for vector <- matrix["vectors"],
        String.starts_with?(vector["case"], "B1-R2-"),
        vector["native"] != true do
      env = Map.merge(matrix["base"], vector["changes"]) |> Map.put("DAWARICH_RAILS", "off")
      url = env["DATABASE_SESSION_URL"]
      assert Lifecycle.mode(env) == {:error, :cloud_native_lifecycle}, vector["case"]
      refute EndpointURL.session?(url, env), vector["case"]

      masked =
        env
        |> Map.put("DATABASE_URL", "postgres://unrelated.invalid/cloud")
        |> Map.delete("DATABASE_POOLING_MODE")

      configs =
        case URI.new(env["DATABASE_URL"]) do
          {:ok, pooled} ->
            [
              [hostname: pooled.host, port: pooled.port || 5432],
              [endpoints: [{pooled.host, pooled.port || 5432}]],
              [url: env["DATABASE_URL"]]
            ]

          _ ->
            [[url: env["DATABASE_URL"]]]
        end

      for config <- configs do
        Process.put(:endpoint_repo_config, config ++ [pool_mode: env["DATABASE_POOLING_MODE"]])
        assert refused?(url, masked), vector["case"]
      end

      for rails <- ["off", "proxy"] do
        opts = [
          env:
            Map.merge(env, %{"DAWARICH_RAILS" => rails, "DAWARICH_PHOENIX_LIFECYCLE" => "true"}),
          repos: [ConfigRepo]
        ]

        for call <- [
              fn -> Dawarich.Release.migrate(opts) end,
              fn -> Dawarich.Release.seed(opts) end,
              fn -> Dawarich.Release.Native.migrate(ConfigRepo, opts) end,
              fn -> Dawarich.Release.Native.seed(ConfigRepo, opts) end
            ] do
          assert_raise RuntimeError, ~r/native lifecycle requires self-hosted mode/, call
        end

        refute Dawarich.Release.Native.ready?(ConfigRepo, opts)
        refute_received :unexpected_endpoint_query
      end
    end

    for mode <- ["transaction", "statement"],
        host <- ["::ffff:127.0.0.1", "[::FFFF:7f00:1]", "::127.0.0.1", "[::7f00:1]"] do
      env = Map.put(matrix["base"], "DATABASE_URL", "postgres://unrelated.invalid/cloud")

      for config <- [[hostname: host], [endpoints: [{host, 5432}]]] do
        Process.put(:endpoint_repo_config, config ++ [pool_mode: mode, socket_options: [:inet6]])
        assert refused?("postgres://127.0.0.1/cloud", env)
      end
    end

    for host <- ["fe80::1%25eth0", "::ffff:gggg:1", "[::ffff:gggg:1]"] do
      Process.put(:endpoint_repo_config, hostname: host, pool_mode: "transaction")
      assert refused?("postgres://192.0.2.10/cloud", matrix["base"])
    end

    for vector <- matrix["vectors"], vector["native"] == true do
      env = Map.merge(matrix["base"], vector["changes"]) |> Map.put("DAWARICH_RAILS", "off")
      assert Lifecycle.mode(env) == {:ok, :native}, vector["case"]
      pooled = URI.parse(env["DATABASE_URL"])

      Process.put(:endpoint_repo_config,
        hostname: pooled.host,
        port: pooled.port || 5432,
        pool_mode: "transaction"
      )

      assert accepted?(env["DATABASE_SESSION_URL"], env), vector["case"]
    end

    for vector <- matrix["vectors"], String.starts_with?(vector["case"], "B1-R2-noncanonical-") do
      url =
        if String.contains?(vector["case"], "-pool-"),
          do: vector["changes"]["DATABASE_URL"],
          else: vector["changes"]["DATABASE_SESSION_URL"]

      refute EndpointURL.origin?(
               String.replace(url, "postgres://", "https://")
               |> String.replace_suffix("/cloud", "")
             ),
             vector["case"]
    end
  end

  defp refused?(url, env) do
    SessionConnection.check(ConfigRepo, session_url: url, env: env) ==
      {:error, :session_connection_required}
  end

  defp accepted?(url, env) do
    match?({:ok, _}, SessionConnection.check(ConfigRepo, session_url: url, env: env))
  end
end
