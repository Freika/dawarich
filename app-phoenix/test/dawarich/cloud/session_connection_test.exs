defmodule Dawarich.Cloud.SessionConnectionTest.PooledRepo do
  def config, do: Keyword.put(Dawarich.ScratchRepo.config(), :port, 6432)
  defdelegate get_dynamic_repo(), to: Dawarich.ScratchRepo
  defdelegate all(query, opts), to: Dawarich.ScratchRepo
  defdelegate __adapter__(), to: Dawarich.ScratchRepo
  defdelegate query!(sql, args, opts), to: Dawarich.ScratchRepo
  defdelegate checkout(fun), to: Dawarich.ScratchRepo
  defdelegate in_transaction?(), to: Dawarich.ScratchRepo
end

defmodule Dawarich.Cloud.SessionConnectionTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.AfterCommit.Callback
  alias Dawarich.Release.CloudPreflight
  alias __MODULE__.PooledRepo

  test "Cloud preflight refuses a pooled lease endpoint before writes" do
    before = rows("SELECT count(*) FROM phoenix.release_migrator_leases")

    opts = [
      session_url: "postgres://synthetic.invalid:6432/synthetic",
      env: %{
        "SELF_HOSTED" => "false",
        "MANAGER_URL" => "https://manager.example.invalid",
        "JWT_SECRET_KEY" => "synthetic-l1-config"
      },
      command: fn _ -> {:ok, nil} end
    ]

    assert {:error, :session_connection_required} = CloudPreflight.check(ScratchRepo, opts)
    assert rows("SELECT count(*) FROM phoenix.release_migrator_leases") == before
  end

  test "callback refuses a pooled endpoint without delivering or writing a receipt" do
    event = Ecto.UUID.generate()
    parent = self()

    assert {:error, :session_connection_required} =
             Callback.run(PooledRepo, event, "probe", fn ->
               send(parent, :delivered)
               :ok
             end)

    refute_received :delivered
    refute Dawarich.Jobs.Processed.done?(ScratchRepo, event)
  end

  test "callback holds its session lock on a dedicated connection across receipt transactions" do
    event = Ecto.UUID.generate()

    config = ScratchRepo.config()
    previous = Application.get_env(:dawarich, :database_session_url)
    userinfo = URI.encode(config[:username]) <> ":" <> URI.encode(config[:password] || "")

    url =
      URI.to_string(%URI{
        scheme: "postgres",
        host: config[:hostname],
        port: config[:port],
        path: "/" <> config[:database],
        userinfo: userinfo
      })

    Application.put_env(:dawarich, :database_session_url, url)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, :database_session_url, previous),
        else: Application.delete_env(:dawarich, :database_session_url)
    end)

    assert :ok =
             Callback.run(PooledRepo, event, "probe", fn ->
               assert rows(
                        "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND pid=pg_backend_pid()"
                      ) == [[0]]

               assert {:ok, :ok} = ScratchRepo.transaction(fn -> :ok end)

               assert rows(
                        "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND pid=pg_backend_pid()"
                      ) == [[0]]

               :ok
             end)

    assert Dawarich.Jobs.Processed.done?(ScratchRepo, event)
  end

  test "direct session URL preserves database TLS verification settings" do
    assert {:ok, config} =
             Dawarich.Cloud.SessionConnection.check(ScratchRepo,
               session_url: "postgres://synthetic.invalid:5432/synthetic?sslmode=verify-full"
             )

    assert is_list(config[:ssl])
    assert config[:ssl][:verify] == :verify_peer
  end

  test "callback exceptions preserve callback failure and publish no receipt" do
    event = Ecto.UUID.generate()

    assert {:error, :callback_failed} =
             Callback.run(ScratchRepo, event, "probe", fn ->
               raise "synthetic callback failure"
             end)

    refute Dawarich.Jobs.Processed.done?(ScratchRepo, event)
  end
end
