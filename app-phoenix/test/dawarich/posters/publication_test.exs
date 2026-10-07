defmodule Dawarich.Posters.PublicationTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Posters.Publication
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.State.Lease

  setup do
    rows(
      "INSERT INTO users(id,email,created_at,updated_at) VALUES(1,'a9-publication@dawarich.test',now(),now())"
    )

    rows(
      "INSERT INTO posters(id,user_id,name,status,settings,created_at,updated_at) VALUES(1,1,'Synthetic',0,'{}',now(),now())"
    )

    Ownership.put!(ScratchRepo, "command:posters.create", :oban)
    holder = Ecto.UUID.generate()
    assert Lease.acquire(ScratchRepo, "posters:1", holder, 60_000)
    %{holder: holder, event: Ecto.UUID.generate()}
  end

  @tag mutation: "pair"
  test "publication attaches both outputs and completes in one transaction", c do
    assert {:ok, ctx} = Publication.prepare(ScratchRepo, 1, 1, c.event, c.holder, "en")
    blobs = blobs()
    [png, pdf] = blobs

    assert {:error, %Postgrex.Error{}} =
             Publication.publish(ScratchRepo, ctx, [png, %{pdf | key: png.key}])

    assert rows("SELECT status FROM posters WHERE id=1") == [[1]]
    assert rows("SELECT count(*) FROM active_storage_blobs") == [[0]]
    assert rows("SELECT count(*) FROM active_storage_attachments") == [[0]]
    refute Processed.done?(ScratchRepo, c.event)
    assert {:ok, :published} = Publication.publish(ScratchRepo, ctx, blobs)
    assert rows("SELECT status FROM posters WHERE id=1") == [[2]]

    assert rows(
             "SELECT name FROM active_storage_attachments WHERE record_type='Poster' AND record_id=1 ORDER BY name"
           ) == [["image"], ["print_pdf"]]

    assert Processed.done?(ScratchRepo, c.event)

    assert rows(
             "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Posters.ProgressWorker' ORDER BY id"
           )
           |> Enum.all?(fn [payload] ->
             Enum.sort(Map.keys(payload)) == ~w(event_id locale poster_id user_id)
           end)
  end

  @tag mutation: "duplicate"
  test "duplicate completed event produces no second attachment pair", c do
    assert {:ok, ctx} = Publication.prepare(ScratchRepo, 1, 1, c.event, c.holder, "de")
    assert {:ok, :published} = Publication.publish(ScratchRepo, ctx, blobs())
    before = rows("SELECT id,key FROM active_storage_blobs ORDER BY id")
    assert {:ok, :duplicate} = Publication.publish(ScratchRepo, ctx, blobs())
    assert rows("SELECT id,key FROM active_storage_blobs ORDER BY id") == before
    assert rows("SELECT count(*) FROM active_storage_attachments") == [[2]]
  end

  @tag mutation: "terminal"
  test "native progress re renders current owner row and cannot overwrite completed with failed",
       c do
    assert {:ok, ctx} = Publication.prepare(ScratchRepo, 1, 1, c.event, c.holder, "de")
    rows("UPDATE posters SET name='Current',settings='{}' WHERE id=1")
    assert {:ok, :updated} = Publication.progress(ScratchRepo, ctx, "drawing_map")

    assert rows("SELECT name,settings FROM posters WHERE id=1") == [
             ["Current", %{"progress_phase" => "drawing_map"}]
           ]

    rows("UPDATE posters SET status=2 WHERE id=1")
    assert {:ok, :skip} = Publication.fail(ScratchRepo, ctx, "failed")

    assert rows("SELECT status,settings FROM posters WHERE id=1") == [
             [2, %{"progress_phase" => "drawing_map"}]
           ]

    assert [[payload]] =
             rows(
               "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Posters.ProgressWorker' ORDER BY id DESC LIMIT 1"
             )

    assert Map.drop(payload, ["event_id"]) == %{
             "poster_id" => 1,
             "user_id" => 1,
             "locale" => "de"
           }

    assert {:ok, :skip} = Publication.progress(ScratchRepo, ctx, "saving")
  end

  defp blobs do
    for {filename, type} <- [{"poster_1.png", "image/png"}, {"poster_1.pdf", "application/pdf"}] do
      %{
        key: Dawarich.Storage.generate_key(),
        filename: filename,
        content_type: type,
        service_name: "local",
        byte_size: 3,
        checksum: "CY9rzUYh03PK3k6DJie09g==",
        metadata: "{}"
      }
    end
  end
end
