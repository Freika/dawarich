defmodule Dawarich.EnhancedImport.ExtractionDeadlineTest do
  use Dawarich.EnhancedImportCase

  alias Dawarich.EnhancedImport.ExtractGpxWorker
  alias Dawarich.Storage
  alias Dawarich.Tracks.PerUserLock

  defmodule BlockedClient do
    @moduledoc false
    @behaviour ExAws.Request.HttpClient

    @impl true
    def request(:get, _url, _body, _headers, opts) do
      send(Keyword.fetch!(opts, :caller), {:blocked, self()})

      receive do
        :release -> :ok
      after
        1_000 -> :ok
      end

      xml = "<gpx/>"
      {:ok, %{status_code: 206, headers: [{"content-range", "bytes 0-5/6"}], body: xml}}
    end
  end

  setup do
    previous = Application.fetch_env!(:dawarich, :extraction_timeout_ms)
    Application.put_env(:dawarich, :extraction_timeout_ms, 60_200)
    on_exit(fn -> Application.put_env(:dawarich, :extraction_timeout_ms, previous) end)
    :ok
  end

  defp prepare(storage, xml) do
    fixture = load!("writer_dedup")
    [import] = fixture["input"]["imports"]

    attach!(storage, %{
      "import_id" => import["id"],
      "filename" => "deadline.gpx",
      "content_type" => "application/gpx+xml",
      "byte_size" => byte_size(xml),
      "checksum" => Base.encode64(:crypto.hash(:md5, xml)),
      "base64" => Base.encode64(xml)
    })

    {import["id"], import["user_id"]}
  end

  defp run(id, attempt, storage, repo \\ ScratchRepo, opts \\ []) do
    job = %Oban.Job{
      args: %{"import_id" => id, "lock_attempt" => 1, "event_id" => Ecto.UUID.generate()},
      attempt: attempt,
      max_attempts: 3,
      meta: %{}
    }

    assert_raise RuntimeError, "GPX extraction did not finish within 0 minutes", fn ->
      ExtractGpxWorker.run(repo, job, [storage: storage] ++ opts)
    end
  end

  defp assert_cleanup(storage, uid) do
    assert_received {:blocked, pid}
    refute Process.alive?(pid)
    assert Path.wildcard(Path.join(storage.root, ".phoenix-tmp/*")) == []
    assert lease_holders(ScratchRepo, PerUserLock.key(uid)) == []
  end

  for {attempt, status} <- [{1, 1}, {3, 4}] do
    test "a blocked source read records the attempt #{attempt} failure and is cancelled", %{
      storage: storage
    } do
      {id, uid} = prepare(storage, "<gpx/>")

      s3 =
        Storage.config!(%{
          "STORAGE_BACKEND" => "s3",
          "AWS_ACCESS_KEY_ID" => "AKIA",
          "AWS_SECRET_ACCESS_KEY" => "synthetic",
          "AWS_REGION" => "eu-central-1",
          "AWS_BUCKET" => "dawarich"
        })

      s3 = %{
        s3
        | root: storage.root,
          ex_aws:
            Keyword.merge(s3.ex_aws, http_client: BlockedClient, http_opts: [caller: self()])
      }

      run(id, unquote(attempt), s3)

      assert {unquote(status),
              %{"error_message" => "GPX extraction did not finish within 0 minutes"},
              _} =
               import_state(id)

      assert_cleanup(storage, uid)

      assert Enum.any?(kinds(), &(&1["kind"] == "schedule_untracked_tracks")) ==
               (unquote(attempt) == 3)
    end
  end

  test "a blocked place write is cancelled before the final failure and lock release", %{
    storage: storage
  } do
    xml = ~s(<gpx><wpt lat="51.9" lon="12.9"><name>TimeoutPin</name></wpt></gpx>)
    {id, uid} = prepare(storage, xml)
    caller = self()

    HookRepo.set_hook(fn sql, _params ->
      if sql =~ "INSERT INTO places" do
        send(caller, {:blocked, self()})

        receive do
          :release -> :ok
        after
          1_000 -> :ok
        end
      end

      :ok
    end)

    run(id, 3, storage, HookRepo)

    assert {4, %{"error_message" => "GPX extraction did not finish within 0 minutes"}, _} =
             import_state(id)

    assert_cleanup(storage, uid)
    assert List.last(kinds())["kind"] == "schedule_untracked_tracks"
    assert rows("SELECT count(*) FROM places WHERE name = 'TimeoutPin'") == [[0]]
  end

  test "a real stalled S3 request is closed and the final failure releases extraction", %{
    storage: storage
  } do
    {id, uid} = prepare(storage, "<gpx/>")
    Application.put_env(:dawarich, :extraction_timeout_ms, 60_000)
    server = Dawarich.Test.RawHTTP.listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)
    caller = self()

    peer =
      Task.async(fn ->
        socket = Dawarich.Test.RawHTTP.accept(server)
        Dawarich.Test.RawHTTP.read_head(socket)
        :ok = :gen_tcp.controlling_process(socket, caller)
        socket
      end)

    s3 =
      Storage.config!(%{
        "STORAGE_BACKEND" => "s3",
        "AWS_ACCESS_KEY_ID" => "AKIA",
        "AWS_SECRET_ACCESS_KEY" => "synthetic",
        "AWS_REGION" => "eu-central-1",
        "AWS_BUCKET" => "dawarich",
        "AWS_ENDPOINT_URL" => "http://127.0.0.1:#{server.port}"
      })

    deadline = %{at: :deferred, timeout_ms: 200, minutes: 0}

    extraction =
      Task.async(fn ->
        run(id, 3, %{s3 | root: storage.root}, ScratchRepo, deadline: deadline)
      end)

    socket = Task.await(peer, :infinity)
    send(extraction.pid, :start_deadline)

    assert %RuntimeError{message: "GPX extraction did not finish within 0 minutes"} =
             Task.await(extraction)

    assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1_000)

    assert {4, %{"error_message" => "GPX extraction did not finish within 0 minutes"}, _} =
             import_state(id)

    assert List.last(kinds())["kind"] == "schedule_untracked_tracks"
    assert Path.wildcard(Path.join(storage.root, ".phoenix-tmp/*")) == []
    assert lease_holders(ScratchRepo, PerUserLock.key(uid)) == []
  end
end
