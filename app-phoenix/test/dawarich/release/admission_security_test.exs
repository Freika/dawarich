defmodule Dawarich.Release.AdmissionSecurityTest do
  use ExUnit.Case, async: false
  alias Dawarich.Release.Lifecycle
  alias Dawarich.Cloud.SessionConnection

  defmodule ConfigRepo do
    def config, do: Process.get(:admission_repo_config)
  end

  @env %{
    "SELF_HOSTED" => "false",
    "DAWARICH_RAILS" => "off",
    "MANAGER_URL" => "https://manager.example.invalid",
    "JWT_SECRET_KEY" => "synthetic-review-key",
    "DATABASE_SESSION_URL" => "postgres://session.example.invalid/cloud"
  }

  test "B1 known pooled endpoints cannot be reused through normalized session URLs" do
    for mode <- ["transaction", "statement"],
        url <- [
          "postgres://pool.example.invalid:5432/cloud",
          "postgresql://other:synthetic@POOL.EXAMPLE.INVALID.:05432/%63loud?sslmode=require"
        ] do
      env =
        Map.merge(@env, %{
          "DATABASE_POOLING_MODE" => mode,
          "DATABASE_URL" => "postgres://pool.example.invalid/cloud",
          "DATABASE_SESSION_URL" => url
        })

      assert Lifecycle.mode(env) == {:error, :cloud_native_lifecycle}

      Process.put(:admission_repo_config,
        hostname: "pool.example.invalid",
        port: 5432,
        database: "cloud",
        pool_mode: mode
      )

      assert session_refused?(url, env)

      masked =
        env
        |> Map.put("DATABASE_URL", "postgres://direct.example.invalid/cloud")
        |> Map.delete("DATABASE_POOLING_MODE")

      assert session_refused?(url, masked)

      direct = "postgres://direct.example.invalid/cloud"
      assert Lifecycle.mode(Map.put(env, "DATABASE_SESSION_URL", direct)) == {:ok, :native}
      assert {:ok, _} = SessionConnection.check(ConfigRepo, session_url: direct, env: env)
    end

    for mode <- ["transaction", "statement"] do
      env =
        Map.merge(@env, %{
          "DATABASE_POOLING_MODE" => mode,
          "DATABASE_URL" => "postgres://[::1]/cloud",
          "DATABASE_SESSION_URL" => "postgres://[0:0:0:0:0:0:0:1]:05432/cloud"
        })

      assert Lifecycle.mode(env) == {:error, :cloud_native_lifecycle}
    end

    for url <- [
          "postgres://pgbouncer.example.invalid/cloud",
          "postgres://pool.example.invalid:06432/cloud",
          "postgres://pool.example.invalid/cloud?pgbouncer=true"
        ] do
      assert Lifecycle.mode(Map.put(@env, "DATABASE_SESSION_URL", url)) ==
               {:error, :cloud_native_lifecycle}
    end
  end

  test "B2 malformed and ambiguous database and Manager URLs fail closed" do
    for {key, values} <- [
          {"DATABASE_SESSION_URL",
           [
             "postgres:// /cloud",
             "postgres://db.invalid/ ",
             "postgres://db.invalid/%20",
             "postgres://db.invalid:0/cloud",
             "postgres://db.invalid:99999/cloud",
             "postgres://db_example.invalid/cloud",
             "postgres://db.invalid/cloud?pool_mode=transaction&pool_mode=session",
             "postgres://db.invalid/cloud?pool_mode=session&pooling_mode=session",
             "postgres://db.invalid/cloud?sslmode=require&sslmode=disable",
             "garbage\npostgres://db.invalid/cloud",
             "postgres://db.invalid/%ZZ",
             "postgres://db.invalid/cloud?host=other.invalid",
             "postgres://127.1/cloud",
             "postgres://0x7f.0.0.1/cloud",
             "postgres://db.invalid//cloud",
             "postgres://db.invalid../cloud"
           ]},
          {"MANAGER_URL",
           [
             "https://manager.invalid:0",
             "https://manager.invalid:99999",
             "https://manager_example.invalid",
             "https://[::1]",
             "garbage\nhttps://manager.invalid",
             "https://127.1",
             "https://-manager.invalid"
           ]}
        ],
        value <- values do
      assert Lifecycle.mode(Map.put(@env, key, value)) == {:error, :cloud_native_lifecycle}
    end
  end

  test "B2 all 648 reviewer cases have identical shell and Elixir admission decisions" do
    matrix = File.read!("test/fixtures/cloud_admission_matrix.json") |> Jason.decode!()
    vectors = Enum.reject(matrix["vectors"], &String.starts_with?(&1["case"], "B1-R2-"))
    assert length(vectors) * 12 == 648
    assert_matrix(Map.put(matrix, "vectors", vectors))
  end

  test "B1-R2 shared host matrix refuses all 30 reviewer aliases with identical shell and Elixir decisions" do
    matrix = File.read!("test/fixtures/cloud_admission_matrix.json") |> Jason.decode!()
    vectors = Enum.filter(matrix["vectors"], &String.starts_with?(&1["case"], "B1-R2-"))
    assert length(vectors) * 12 == 732
    assert_matrix(Map.put(matrix, "vectors", vectors))
  end

  defp assert_matrix(matrix) do
    rows =
      for vector <- matrix["vectors"],
          rails <- [nil, "proxy", "off"],
          flag <- [nil, "false", "true", "invalid"] do
        env =
          Map.merge(matrix["base"], vector["changes"])
          |> Map.put("DAWARICH_RAILS", rails)
          |> Map.put("DAWARICH_PHOENIX_LIFECYCLE", flag)
          |> Enum.reject(fn {_, value} -> is_nil(value) end)
          |> Map.new()

        %{"case" => vector["case"], "env" => env, "native" => vector["native"] == true}
      end

    root = Path.expand("..")
    dir = Path.join(System.tmp_dir!(), "admission-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, packet: :line, active: false, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    server = Task.async(fn -> serve(listener) end)
    on_exit(fn -> :gen_tcp.close(listener) end)
    wrapper = Path.join(dir, "dawarich")

    File.write!(wrapper, """
    #!/usr/bin/env python3
    import json, os, socket, sys
    if sys.argv[1:] != ['eval', 'if !Dawarich.Release.Lifecycle.admitted?(), do: System.halt(1)']:
        sys.exit(2)
    with socket.create_connection(('127.0.0.1', #{port})) as s:
        env={k:v for k,v in os.environ.items() if k in #{inspect(Enum.uniq(Enum.flat_map(rows, &Map.keys(&1["env"]))))}}
        s.sendall((json.dumps(env)+'\\n').encode())
        sys.exit(0 if s.recv(16).strip() == b'true' else 1)
    """)

    File.chmod!(wrapper, 0o755)
    env_path = Path.join(dir, "rows.json")
    File.write!(env_path, Jason.encode!(rows))

    script = """
    import json, os, subprocess, sys
    rows=json.load(open(sys.argv[1]))
    keys=set().union(*(r['env'].keys() for r in rows))
    base={k:v for k,v in os.environ.items() if k not in keys}
    base['PATH']=sys.argv[2]+os.pathsep+base['PATH']
    for i,row in enumerate(rows):
        p=subprocess.run(['/bin/sh','-c','. "$1"; validate_native_admission',
            'release.sh',sys.argv[3]],env=base|row['env'],capture_output=True)
        row['allow']=p.returncode==0
        row['leak']=any(m in p.stdout+p.stderr for m in [b'synthetic-review-key',b'synthetic:synthetic'])
    print(json.dumps(rows))
    """

    try do
      {out, 0} =
        System.cmd(
          "python3",
          ["-c", script, env_path, dir, Path.join(root, "docker/entrypoint-env-guard.sh")],
          stderr_to_stdout: true
        )

      for row <- Jason.decode!(out) do
        result = Lifecycle.mode(row["env"])
        assert row["allow"] == result in [{:ok, :native}, {:ok, :rails}], row["case"]
        refute row["leak"], row["case"]

        if row["env"]["DAWARICH_PHOENIX_LIFECYCLE"] == "true" or
             row["env"]["DAWARICH_RAILS"] == "off" do
          if (row["native"] or row["case"] in ["valid", "session_tls"]) and
               row["env"]["DAWARICH_PHOENIX_LIFECYCLE"] != "invalid" do
            assert result == {:ok, :native}, row["case"]
          else
            refute result == {:ok, :native}, row["case"]
          end
        end
      end
    after
      :gen_tcp.close(listener)
      Task.await(server)
    end
  end

  defp session_refused?(url, env) do
    SessionConnection.check(ConfigRepo, session_url: url, env: env) ==
      {:error, :session_connection_required}
  end

  defp serve(listener) do
    case :gen_tcp.accept(listener) do
      {:ok, client} ->
        {:ok, line} = :gen_tcp.recv(client, 0)
        result = Lifecycle.admitted?(Jason.decode!(line))
        :gen_tcp.send(client, "#{result}\n")
        :gen_tcp.close(client)
        serve(listener)

      {:error, :closed} ->
        :ok
    end
  end
end
