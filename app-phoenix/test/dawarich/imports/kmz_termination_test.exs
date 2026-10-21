defmodule Dawarich.Imports.KmzTerminationTest do
  use Dawarich.JobsCase
  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.Imports.ProcessWorker
  alias Dawarich.Jobs.{Ownership, Registry}

  setup do
    c = F.setup()
    previous = Application.fetch_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)

    on_exit(fn ->
      case previous do
        {:ok, repo} -> Application.put_env(:dawarich, :jobs_repo, repo)
        :error -> Application.delete_env(:dawarich, :jobs_repo)
      end
    end)

    for entry <- Registry.entries(), do: Ownership.put!(ScratchRepo, entry.key, :oban)
    start_oban(__MODULE__)
    c
  end

  test "multi-entry KMZ queues only members and terminates with zero-timestamp warning", c do
    c = archive(c, "journey.kmz", kmz())
    assert {:snooze, 5} = ProcessWorker.perform(c.job)
    assert filenames() == ["doc.kml", "journey.kmz"]
    drain()
    assert filenames() == ["doc.kml"]
    assert rows("SELECT status,raw_points FROM imports") == [[2, 0]]
    assert [[content]] = rows("SELECT content FROM notifications WHERE kind=1")
    assert content =~ "timestamps"
    assert rows("SELECT count(*) FROM points") == [[0]]
  end

  test "single-entry KMZ completes without source children", c do
    c = archive(c, "single.kmz", zip([{"doc.kml", kml()}]))
    assert :ok = ProcessWorker.perform(c.job)
    assert filenames() == ["single.kmz"]
    assert rows("SELECT status,raw_points FROM imports") == [[2, 0]]
    assert rows("SELECT child_id FROM phoenix.import_archive_children") == []
  end

  test "legitimate nested staging-name KMZ remains importable and terminates", c do
    c =
      archive(c, "collection.kmz", zip([{"nested/_source.kmz", kmz()}, {"readme.txt", "nested"}]))

    assert {:snooze, 5} = ProcessWorker.perform(c.job)
    assert filenames() == ["_source.kmz", "collection.kmz"]
    drain()
    assert filenames() == ["doc.kml"]
    assert rows("SELECT status,raw_points FROM imports") == [[2, 0]]
    assert rows("SELECT count(*) FROM points") == [[0]]
  end

  defp archive(c, filename, bytes) do
    F.blob(c, filename, bytes, "file")
    rows("UPDATE imports SET name=$2,source=NULL WHERE id=$1", [c.import.id, filename])

    rows("UPDATE oban.oban_jobs SET worker='Dawarich.Imports.ProcessWorker' WHERE id=$1", [
      c.job.id
    ])

    c
  end

  defp drain do
    for _ <- 1..4 do
      jobs =
        rows(
          "SELECT j.id,j.args FROM oban.oban_jobs j JOIN imports i ON i.id=(j.args->>'import_id')::bigint WHERE j.worker='Dawarich.Imports.ProcessWorker' AND i.status IN (0,1) ORDER BY j.id"
        )

      for [id, args] <- jobs do
        rows("UPDATE oban.oban_jobs SET state='executing',attempt=1 WHERE id=$1", [id])
        result = ProcessWorker.perform(%Oban.Job{id: id, args: args, attempt: 1})
        assert result in [:ok, {:snooze, 5}]
      end
    end

    assert rows("SELECT id FROM imports WHERE status IN (0,1)") == []
  end

  defp filenames do
    rows(
      "SELECT b.filename FROM active_storage_blobs b JOIN active_storage_attachments a ON a.blob_id=b.id JOIN imports i ON i.id=a.record_id WHERE a.record_type='Import' ORDER BY b.filename"
    )
    |> List.flatten()
  end

  defp kmz, do: zip([{"doc.kml", kml()}, {"images/icon.png", <<137, 80, 78, 71>>}])

  defp kml,
    do:
      ~s(<kml xmlns="http://www.opengis.net/kml/2.2"><Document><Placemark><Point><coordinates>13.4,52.5,0</coordinates></Point></Placemark></Document></kml>)

  defp zip(entries) do
    {:ok, {_, bytes}} =
      :zip.create(
        ~c"input.kmz",
        Enum.map(entries, fn {name, bytes} -> {String.to_charlist(name), bytes} end),
        [:memory]
      )

    bytes
  end
end
