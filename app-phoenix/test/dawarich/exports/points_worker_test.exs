defmodule Dawarich.Exports.PointsWorkerTest do
  use Dawarich.JobsCase
  use Oban.Testing, repo: Dawarich.ScratchRepo

  alias Dawarich.Exports.PointsWorker

  defmodule AmbiguousCommitRepo do
    @moduledoc false
    alias Dawarich.ScratchRepo

    def query!(sql, params, opts) do
      if sql =~ "SET status = 2", do: Process.put(:commit_armed, true)
      ScratchRepo.query!(sql, params, opts)
    end

    def rollback(value), do: ScratchRepo.rollback(value)
    defdelegate in_transaction?(), to: ScratchRepo

    def transaction(fun) do
      outer? = not ScratchRepo.in_transaction?()
      result = ScratchRepo.transaction(fun)

      if outer? and Process.delete(:commit_armed),
        do: raise(DBConnection.ConnectionError, "connection closed while awaiting COMMIT")

      result
    end
  end

  @payloads "test/fixtures/wave2/payloads.json" |> File.read!() |> Jason.decode!()

  setup do
    Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(public.exports))
    root = Path.join(System.tmp_dir!(), "w2-worker-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    backend = System.get_env("STORAGE_BACKEND")
    System.delete_env("STORAGE_BACKEND")

    on_exit(fn ->
      File.rm_rf!(root)
      if backend, do: System.put_env("STORAGE_BACKEND", backend)
    end)

    [[user_id]] =
      rows(
        "INSERT INTO users (email, created_at, updated_at) VALUES ('w@example.test', now(), now()) RETURNING id"
      )

    rows(
      "INSERT INTO points (user_id, timestamp, lonlat, created_at, updated_at) VALUES ($1, 1774748800, ST_SetSRID(ST_MakePoint(13.4, 0.00005), 4326)::geography, now(), now())",
      [user_id]
    )

    %{root: root, storage: Path.join(root, "storage"), user_id: user_id}
  end

  defp export!(user_id, format \\ 0) do
    [[id]] =
      rows(
        """
        INSERT INTO exports (name, status, file_format, file_type, start_at, end_at, user_id, created_at, updated_at)
        VALUES ('points.json', 0, $2, 0, '2026-03-29 00:00:00', '2026-03-30 00:00:00', $1, now(), now())
        RETURNING id
        """,
        [user_id, format]
      )

    id
  end

  defp perform!(root, user_id, export_id, event_id \\ Ecto.UUID.generate()) do
    File.cd!(root, fn ->
      perform_job(PointsWorker, %{
        "event_id" => event_id,
        "export_id" => export_id,
        "user_id" => user_id
      })
    end)
  end

  defp objects(storage), do: Path.wildcard(Path.join(storage, "??/??/*"))
  defp temp_dirs(storage), do: Path.wildcard(Path.join([storage, ".phoenix-tmp", "*"]))

  defp failed!(export_id) do
    assert [[3, message]] =
             rows("SELECT status, error_message FROM exports WHERE id = $1", [export_id])

    assert [[2, "Export failed", content]] =
             rows("SELECT kind, title, content FROM notifications")

    {message, content}
  end

  test "perform success: one object, status completed, no temp dir left", %{
    root: root,
    storage: storage,
    user_id: user_id
  } do
    id = export!(user_id)

    assert perform!(root, user_id, id) == :ok

    assert [path] = objects(storage)

    assert [[key, "points.json.zip", "local"]] =
             rows("SELECT key, filename, service_name FROM active_storage_blobs")

    assert Path.basename(path) == key
    assert {:ok, [{~c"points.json", payload}]} = :zip.unzip(to_charlist(path), [:memory])
    assert payload =~ ~s("coordinates":[13.4,5e-05])
    assert payload =~ ~s("latitude":"5.0e-05","longitude":"13.4")
    assert rows("SELECT status FROM exports WHERE id = $1", [id]) == [[2]]
    assert rows("SELECT record_id FROM active_storage_attachments") == [[id]]
    assert [[0, "Export finished", _]] = rows("SELECT kind, title, content FROM notifications")
    assert temp_dirs(storage) == []
  end

  test "perform :lost deletes the uploaded object", %{
    root: root,
    storage: storage,
    user_id: user_id
  } do
    rows("""
    CREATE OR REPLACE FUNCTION phoenix.w2_test_stale_recovery() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      UPDATE public.exports SET status = 3 WHERE id = NEW.export_id;
      RETURN NEW;
    END $$
    """)

    rows(
      "CREATE TRIGGER w2_test_stale_recovery AFTER INSERT ON phoenix.export_claims FOR EACH ROW EXECUTE FUNCTION phoenix.w2_test_stale_recovery()"
    )

    on_exit(fn ->
      ScratchRepo.query!("DROP TRIGGER IF EXISTS w2_test_stale_recovery ON phoenix.export_claims")
      ScratchRepo.query!("DROP FUNCTION IF EXISTS phoenix.w2_test_stale_recovery()")
    end)

    id = export!(user_id)

    assert perform!(root, user_id, id) == :ok

    assert objects(storage) == []
    assert rows("SELECT count(*) FROM active_storage_blobs") == [[0]]
    assert rows("SELECT status FROM exports WHERE id = $1", [id]) == [[3]]
    assert rows("SELECT count(*) FROM notifications") == [[0]]
  end

  test "an unknown COMMIT outcome keeps the object: the landed completion still downloads", %{
    root: root,
    storage: storage,
    user_id: user_id
  } do
    Application.put_env(:dawarich, :jobs_repo, AmbiguousCommitRepo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, ScratchRepo) end)
    id = export!(user_id)

    assert_raise DBConnection.ConnectionError, fn -> perform!(root, user_id, id) end

    assert rows("SELECT status FROM exports WHERE id = $1", [id]) == [[2]]
    assert [[key]] = rows("SELECT key FROM active_storage_blobs")
    assert [path] = objects(storage)
    assert Path.basename(path) == key
    assert temp_dirs(storage) == []
  end

  test "perform generation error: failed, error notification, no object, no temp dir, returns :ok",
       %{root: root, storage: storage, user_id: user_id} do
    id = export!(user_id, 2)

    assert perform!(root, user_id, id) == :ok

    assert failed!(id) ==
             {"Unsupported file format: archive",
              ~s(Export "points.json" failed: Unsupported file format: archive, stacktrace: )}

    assert objects(storage) == []
    assert temp_dirs(storage) == []
  end

  test "perform with STORAGE_BACKEND=azure fails the export visibly", %{
    root: root,
    user_id: user_id
  } do
    System.put_env("STORAGE_BACKEND", "azure")
    on_exit(fn -> System.delete_env("STORAGE_BACKEND") end)
    id = export!(user_id)

    assert perform!(root, user_id, id) == :ok
    assert {~s(unsupported STORAGE_BACKEND "azure"), _} = failed!(id)
  end

  test "TIME_ZONE=Berlin writes the same GPX <time> offset as Europe/Berlin", %{
    root: root,
    storage: storage,
    user_id: user_id
  } do
    saved = System.get_env("TIME_ZONE")

    on_exit(fn ->
      if saved, do: System.put_env("TIME_ZONE", saved), else: System.delete_env("TIME_ZONE")
    end)

    times =
      for zone <- ["Europe/Berlin", "Berlin"] do
        System.put_env("TIME_ZONE", zone)
        id = export!(user_id, 1)

        assert perform!(root, user_id, id) == :ok
        assert rows("SELECT status FROM exports WHERE id = $1", [id]) == [[2]], zone

        [[key]] =
          rows(
            "SELECT b.key FROM active_storage_blobs b JOIN active_storage_attachments a ON a.blob_id = b.id WHERE a.record_id = $1",
            [id]
          )

        [path] = Enum.filter(objects(storage), &(Path.basename(&1) == key))
        {:ok, [{_, payload}]} = :zip.unzip(to_charlist(path), [:memory])
        Regex.run(~r/<time>[^<]+<\/time>/, payload)
      end

    time = ["<time>2026-03-29T03:46:40+02:00</time>"]
    assert times == [time, time]
  end

  test "decoder: exact payload only; other versions unsupported; args hold no personal data" do
    payload = @payloads["exports.points"]

    assert PointsWorker.args_from_command(1, payload) == {:ok, payload}
    assert Enum.all?(Map.values(payload), &is_integer/1)

    assert PointsWorker.args_from_command(1, Map.put(payload, "email", "u@example.test")) ==
             {:error, "invalid_payload"}

    assert PointsWorker.args_from_command(1, %{payload | "export_id" => "11"}) ==
             {:error, "invalid_payload"}

    assert PointsWorker.args_from_command(1, Map.delete(payload, "user_id")) ==
             {:error, "invalid_payload"}

    assert PointsWorker.args_from_command(2, payload) == {:error, "invalid_payload"}
    assert PointsWorker.args_from_command(3, payload) == {:error, "unsupported_version"}
  end

  test "timeout is 55 minutes, below Lifeline's 60" do
    assert PointsWorker.timeout(%Oban.Job{}) == :timer.minutes(55)
    assert PointsWorker.timeout(%Oban.Job{}) < :timer.minutes(60)
  end
end
