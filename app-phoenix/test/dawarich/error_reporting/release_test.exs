defmodule Dawarich.ErrorReporting.ReleaseTest do
  use ExUnit.Case, async: false
  import Dawarich.ErrorReportingCase, only: [assert_private: 1]

  defmodule Receiver do
    def init(opts), do: opts

    def call(conn, {pid, status}) do
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(pid, {:release_envelope, body})
      Plug.Conn.send_resp(conn, status, "{}")
    end
  end

  setup_all do
    root = Path.join(Application.fetch_env!(:dawarich, :test_tmp_dir), "sentry-release")
    path = Path.join(root, "release")
    File.mkdir_p!(root)

    {output, status} =
      System.cmd("mix", ["release", "--overwrite", "--path", path],
        env: [{"MIX_ENV", "test"}, {"ERL_FLAGS", "+S 2:2"}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    on_exit(fn -> File.rm_rf!(root) end)
    %{release: Path.join(path, "bin/dawarich"), root: root}
  end

  test "release migrate seed and maintenance failures report before nonzero exit without starting web",
       ctx do
    bandit =
      start_supervised!({Bandit, plug: {Receiver, {self(), 200}}, ip: {127, 0, 0, 1}, port: 0})

    {:ok, {_, port}} = ThousandIsland.listener_info(bandit)

    for args <- [["migrate"], ["seeds"], ["users", "activate"], ["eval-migrate"], ["eval-seed"]] do
      {output, status} = run_release(ctx, port, args)
      assert status == 1, output
      assert output =~ "web_started=false"
      assert_receive {:release_envelope, body}, 1_000
      [_, item, payload] = String.split(body, "\n", parts: 3)
      assert Jason.decode!(item)["type"] == "event"
      payload = payload |> String.trim() |> Jason.decode!()
      assert payload["tags"]["surface"] == "release"
      assert hd(payload["exception"])["stacktrace"]["frames"] != []
      assert_private(payload)
      refute body =~ "synthetic-db-password"
      refute body =~ "postgres://"
      refute_receive {:release_envelope, _}
    end
  end

  test "release transport failure preserves the original error and exit", ctx do
    bandit =
      start_supervised!({Bandit, plug: {Receiver, {self(), 503}}, ip: {127, 0, 0, 1}, port: 0})

    {:ok, {_, port}} = ThousandIsland.listener_info(bandit)
    {output, status} = run_release(ctx, port, ["migrate"])
    assert status == 1
    assert output =~ "dawarich: refused: DAWARICH_PHOENIX_LIFECYCLE must be true or false"
    assert_receive {:release_envelope, _}, 1_000
    refute_receive {:release_envelope, _}
  end

  defp run_release(ctx, port, args) do
    command =
      case args do
        ["eval-migrate"] -> "Dawarich.Release.migrate()"
        ["eval-seed"] -> "Dawarich.Release.seed()"
        _ -> "Dawarich.CLI.main()"
      end

    code = """
    Application.load(:dawarich)
    reporting = Dawarich.ErrorReporting.Config.from_env(System.get_env(), :prod)
    Application.put_env(:dawarich, :error_reporting, reporting)
    Application.put_all_env(sentry: Dawarich.ErrorReporting.Config.sdk(reporting))
    Application.put_env(:dawarich, Dawarich.Repo, hostname: "127.0.0.1", port: 1,
      username: "synthetic", password: "synthetic-db-password", database: "synthetic_unreachable",
      pool_size: 1, timeout: 100, queue_target: 50, queue_interval: 50)
    IO.puts("web_started=" <> to_string(Process.whereis(DawarichWeb.Endpoint) != nil))
    #{command}
    """

    System.cmd(ctx.release, ["eval", code | args],
      stderr_to_stdout: true,
      env: [
        {"SENTRY_DSN", "http://public@127.0.0.1:#{port}/1"},
        {"ERL_FLAGS", "+S 2:2"},
        {"DAWARICH_COOKIE_FILE", Path.join(ctx.root, "cookie")},
        {"DAWARICH_PHOENIX_LIFECYCLE", "invalid"},
        {"SELF_HOSTED", "true"},
        {"SENTRY_ENABLE_LOGS", "false"},
        {"RELEASE_DISTRIBUTION", "none"}
      ]
    )
  end
end
