defmodule Dawarich.Trips.AttachmentAdmissionTest do
  use Dawarich.DataCase, async: true

  alias Dawarich.Accounts
  alias Dawarich.Accounts.Scope
  alias Dawarich.RailsMessages
  alias Dawarich.Storage.UploadReceipts
  alias Dawarich.Test.TripsSeeds
  alias Dawarich.Trips.{AttachmentAdmission, Commands, Description}

  @now ~U[2026-10-03 10:00:00.000000Z]
  @stamp ~N[2026-10-03 10:00:00]

  defp scope(id) do
    TripsSeeds.user!(id)
    Scope.for_user(Accounts.get(id), "en")
  end

  defp blob!(name, metadata \\ %{"identified" => true, "analyzed" => true}) do
    [[id]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES($1,$2,'text/plain',$3,'local',9,'synthetic',$4) RETURNING id",
        [Ecto.UUID.generate(), name, Jason.encode!(metadata), @stamp]
      )

    id
  end

  defp embed(id),
    do:
      ~s(<action-text-attachment sgid="#{RailsMessages.attachable_sgid(id)}"></action-text-attachment>)

  defp described!(scope, trip_id, body) do
    TripsSeeds.trip!(%{id: trip_id, user_id: scope.user.id})
    TripsSeeds.rich_text!(trip_id, body)
    [[rich]] = rows("SELECT id FROM action_text_rich_texts WHERE record_id=$1", [trip_id])
    rich
  end

  defp attach!(rich, blob),
    do:
      rows(
        "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('embeds','ActionText::RichText',$1,$2,$3)",
        [rich, blob, @stamp]
      )

  defp graph(rich),
    do:
      rows(
        "SELECT blob_id FROM active_storage_attachments WHERE record_type='ActionText::RichText' AND record_id=$1 ORDER BY blob_id",
        [rich]
      )

  defp body(trip_id),
    do: rows("SELECT body FROM action_text_rich_texts WHERE record_id=$1", [trip_id])

  defp save(scope, trip_id, body),
    do: Commands.update(scope, trip_id, %{"description" => body}, @now, repo: Repo)

  test "existing rich description round trips without losing legacy embeds" do
    owner = scope(9_701)
    legacy = blob!("legacy.txt")
    stored = "<div>Old #{embed(legacy)}</div>"
    rich = described!(owner, 970_101, stored)
    attach!(rich, legacy)

    assert {:ok, editor} = Description.editor(stored, Repo)
    assert editor =~ "data-trix-attachment"
    assert {:ok, canonical} = Description.canonical(editor, Repo)

    assert {:ok, _} = save(owner, 970_101, String.replace(canonical, "Old", "Edited"))
    assert graph(rich) == [[legacy]]
    assert [[saved]] = body(970_101)
    assert saved =~ "Edited"
    assert saved =~ RailsMessages.attachable_sgid(legacy)
  end

  test "a new foreign upload cannot be attached by another actor" do
    owner = scope(9_702)
    other = scope(9_703)
    rich = described!(owner, 970_201, "<div>Mine</div>")
    foreign = blob!("foreign.txt")
    UploadReceipts.bind!(Repo, foreign, other.user.id)
    own = blob!("own.txt")
    UploadReceipts.bind!(Repo, own, owner.user.id)

    assert save(owner, 970_201, "<div>Take #{embed(foreign)}</div>") ==
             {:error, :attachment_refused}

    assert body(970_201) == [["<div>Mine</div>"]]
    assert graph(rich) == []

    assert AttachmentAdmission.admit(Repo, owner.user.id, rich, [foreign]) ==
             {:error, :attachment_refused}

    assert {:ok, _} = save(owner, 970_201, "<div>Mine #{embed(own)}</div>")
    assert graph(rich) == [[own]]
  end

  test "pending purge and expired capabilities leave body and graph unchanged" do
    owner = scope(9_704)
    rich = described!(owner, 970_401, "<div>Keep</div>")
    pending = blob!("pending.txt", %{"identified" => true, "phoenix_purge_pending" => true})
    UploadReceipts.bind!(Repo, pending, owner.user.id)

    assert save(owner, 970_401, "<div>Gone #{embed(pending)}</div>") == {:error, :unavailable}
    assert body(970_401) == [["<div>Keep</div>"]]
    assert graph(rich) == []

    tampered =
      ~s(<div>Forged <action-text-attachment sgid="forged"></action-text-attachment></div>)

    assert {:ok, _} = save(owner, 970_401, tampered)
    assert graph(rich) == []
    assert {:ok, html} = Description.render(tampered, Repo)
    assert IO.iodata_to_binary(html) =~ "☒</action-text-attachment>"
    refute IO.iodata_to_binary(html) =~ "<figure"
  end

  test "private and public rich output reject unsafe attributes and protocols" do
    hostile =
      ~S|<div onclick="steal()">Hi <a href="javascript:alert(1)">x</a><img src="x" onerror="steal()"><script>steal()</script>| <>
        ~S|<a href="data:text/html;base64,PHNjcmlwdD4=">d</a><span style="background:url(javascript:x)">s</span></div>|

    assert {:ok, html} = Description.render(hostile, Repo)
    html = IO.iodata_to_binary(html)

    for unsafe <- ["javascript:", "onerror", "onclick", "<script", "data:text/html", "style="],
        do: refute(html =~ unsafe, unsafe)

    assert html =~ "trix-content"
    assert html =~ "Hi"
  end

  test "removing an embed keeps another owner's shared blob" do
    owner = scope(9_705)
    other = scope(9_706)
    shared = blob!("shared.txt")
    mine = described!(owner, 970_501, "<div>#{embed(shared)}</div>")
    theirs = described!(other, 970_502, "<div>#{embed(shared)}</div>")
    attach!(mine, shared)
    attach!(theirs, shared)

    assert {:ok, _} = save(owner, 970_501, "<div>No more files</div>")
    assert graph(mine) == []
    assert graph(theirs) == [[shared]]
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [shared]) == [[shared]]
  end

  test "nil and blank descriptions keep embeds until a replacement body" do
    owner = scope(9_707)
    kept = blob!("kept.txt")
    rich = described!(owner, 970_701, "<div>#{embed(kept)}</div>")
    attach!(rich, kept)

    assert {:ok, _} = save(owner, 970_701, "")
    assert graph(rich) == [[kept]]
    assert {:ok, _} = save(owner, 970_701, nil)
    assert graph(rich) == [[kept]]
  end
end
