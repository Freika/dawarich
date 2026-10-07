defmodule Dawarich.Trips.RichAttachmentsTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.{RailsMessages, Storage}
  alias Dawarich.Test.RailsUser
  alias Dawarich.Trips.{RichContent, WebDelete, WebForm, WebWrite}
  @now ~U[2026-10-03 10:00:00.000000Z]

  setup do
    root = Path.join(System.tmp_dir!(), "trip-attachments-" <> Ecto.UUID.generate())
    old_root = Application.fetch_env!(:dawarich, :rails_root)
    old_repo = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :rails_root, root)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)

    start_supervised!(
      {Oban,
       name: __MODULE__,
       repo: ScratchRepo,
       prefix: "oban",
       queues: false,
       plugins: false,
       testing: :manual}
    )

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_root, old_root)
      Application.put_env(:dawarich, :jobs_repo, old_repo)
      File.rm_rf!(root)
    end)

    user =
      RailsUser.insert!(
        %{
          id: 980_440,
          api_key: "",
          email: "trip-rich@example.test",
          settings: %{"timezone" => "UTC"}
        },
        ScratchRepo
      )

    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:trips.calculate", :oban)
    %{root: root, user: user}
  end

  @tag a12f3a_t04_blobs: true
  test "T04: signed trip attachments persist and dependent purge retries storage before rows",
       c do
    {blob, file} = blob(c.root, "text/plain", "auwald.txt")
    {child, child_file} = blob(c.root, "image/png", "auwald.png")

    [[variant]] =
      rows(
        "INSERT INTO active_storage_variant_records(blob_id,variation_digest) VALUES($1,$2) RETURNING id",
        [blob, Ecto.UUID.generate()]
      )

    attach("ActiveStorage::VariantRecord", variant, child, "image")

    assert {:ok, href_html} =
             RichContent.read(
               String.replace(attachment(blob), " sgid=", " href=\"javascript:alert(1)\" sgid="),
               ScratchRepo
             )

    refute href_html =~ "href=", "Rails strips the javascript href from a signed attachment"
    body = "<div>Leipzig<script>alert(1)</script></div>" <> attachment(blob)
    assert {:ok, file_html} = RichContent.read(attachment(blob), ScratchRepo)

    assert file_html ==
             "<action-text-attachment sgid=\"#{RailsMessages.attachable_sgid(blob)}\" content-type=\"text/plain\" filename=\"auwald.txt\" filesize=\"9\"><figure class=\"attachment attachment--file attachment--txt\">\n\n  <figcaption class=\"attachment__caption\">\n      <span class=\"attachment__name\">auwald.txt</span>\n      <span class=\"attachment__size\">9 Bytes</span>\n  </figcaption>\n</figure></action-text-attachment>"

    assert {:ok, trip} =
             WebWrite.run(ScratchRepo, :create, c.user, nil, attrs(body), %{now: @now})

    assert [[rich, ^blob]] =
             rows(
               "SELECT record_id,blob_id FROM active_storage_attachments WHERE record_type='ActionText::RichText'"
             )

    assert {:ok, form} = WebForm.load(ScratchRepo, c.user, trip.id, %{})
    assert form.description =~ "data-trix-attachment"
    assert {:ok, roundtrip} = RichContent.canonical(form.description, ScratchRepo)
    assert roundtrip =~ "sgid="
    assert form.description =~ "auwald.txt"
    refute form.description =~ "<script>"

    assert {:ok, _} =
             WebWrite.run(ScratchRepo, :update, c.user, trip.id, %{"name" => "Renamed"}, %{
               now: @now
             })

    assert rows(
             "SELECT blob_id FROM active_storage_attachments WHERE record_id=$1 AND record_type='ActionText::RichText'",
             [rich]
           ) == [[blob]]

    assert {:error, :not_found} =
             WebDelete.run(ScratchRepo, %{c.user | id: c.user.id + 1}, trip.id, %{})

    assert File.exists?(file)
    assert {:ok, :deleted} = WebDelete.run(ScratchRepo, c.user, trip.id, %{})
    assert rows("SELECT id FROM action_text_rich_texts WHERE id=$1", [rich]) == []

    assert rows("SELECT id FROM active_storage_blobs WHERE id=ANY($1) ORDER BY id", [
             [blob, child]
           ]) == [[blob], [child]]

    [[job_id, args]] =
      rows("SELECT id,args FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker'")

    assert Enum.sort(Enum.map(args["objects"], & &1["blob_id"])) == Enum.sort([blob, child])
    File.rm!(file)
    File.mkdir!(file)
    assert %{success: 0, failure: 1} = Oban.drain_queue(__MODULE__, queue: :exports)

    assert rows("SELECT state,attempt FROM oban.oban_jobs WHERE id=$1", [job_id]) == [
             ["retryable", 1]
           ]

    assert rows("SELECT count(*) FROM active_storage_blobs WHERE id=ANY($1)", [[blob, child]]) ==
             [[2]]

    assert File.exists?(child_file)
    File.rmdir!(file)
    File.write!(file, "synthetic")

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(__MODULE__, queue: :exports, with_scheduled: true)

    refute File.exists?(file)
    refute File.exists?(child_file)
    assert rows("SELECT id FROM active_storage_blobs WHERE id=ANY($1)", [[blob, child]]) == []

    assert :ok =
             Dawarich.Exports.PurgeWorker.run(Jason.decode!(Jason.encode!(args)),
               repo: ScratchRepo
             )

    assert rows("SELECT kind FROM phoenix.rails_commands") == []

    raw =
      "<action-text-attachment content-type=\"text/html\" content=\"&lt;div onclick='bad()'&gt;Safe&lt;script&gt;bad&lt;/script&gt;&lt;/div&gt;\"></action-text-attachment>"

    assert {:ok, content} = RichContent.canonical(raw)
    assert content =~ "content-type=\"text/html\""
    assert :rails = RichContent.read(content)
    signed = RailsMessages.attachable_sgid(9_999_999)
    assert {:ok, missing} = RichContent.read(attachment_sgid(signed), ScratchRepo)
    assert missing =~ "☒"

    for raw <- [
          "<action-text-attachment content-type=\"application/octet-stream\"></action-text-attachment>",
          attachment_sgid("tampered")
        ] do
      assert {:ok, placeholder} = RichContent.read(raw, ScratchRepo)
      assert placeholder =~ "☒"
    end

    assert :rails =
             RichContent.read("<action-text-attachment></action-text-attachment>", ScratchRepo)

    assert :rails =
             RichContent.read(
               String.replace(raw, "content-type=", "sgid=\"tampered\" content-type="),
               ScratchRepo
             )
  end

  @tag a12f3a_t04_shared: true
  test "T04: removing a trip embed retains shared blobs and refuses pending capabilities", c do
    {blob, file} = blob(c.root, "text/plain", "shared.txt")

    assert {:ok, first} =
             WebWrite.run(ScratchRepo, :create, c.user, nil, attrs(attachment(blob)), %{now: @now})

    assert {:ok, second} =
             WebWrite.run(ScratchRepo, :create, c.user, nil, attrs(attachment(blob)), %{now: @now})

    assert {:ok, _} =
             WebWrite.run(
               ScratchRepo,
               :update,
               c.user,
               first.id,
               %{"description" => "<div>Removed</div>"},
               %{now: @now}
             )

    assert rows("SELECT count(*) FROM active_storage_attachments WHERE blob_id=$1", [blob]) == [
             [1]
           ]

    assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker'") ==
             [[0]]

    assert File.exists?(file)
    assert {:ok, :deleted} = WebDelete.run(ScratchRepo, c.user, second.id, %{})

    assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker'") ==
             [[1]]

    assert {:replay, _} =
             WebWrite.run(
               ScratchRepo,
               :update,
               c.user,
               first.id,
               %{"description" => attachment(blob)},
               %{now: @now}
             )

    assert %{success: 1, failure: 0} = Oban.drain_queue(__MODULE__, queue: :exports)
    refute File.exists?(file)
  end

  @tag a12f3a_t04_analysis: true
  test "T04: attached image analysis is native and retryable before metadata publication", c do
    bytes =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAEElEQVR4nGNgGAWjYBTAAAADEAABPywr7AAAAABJRU5ErkJggg=="
      )

    blob =
      Dawarich.RailsBlobFixture.create!(
        ScratchRepo,
        Path.join(c.root, "storage"),
        "auwald.png",
        bytes,
        content_type: "image/png",
        metadata: %{"caption" => "Leipzig"}
      )

    assert {:ok, trip} =
             WebWrite.run(ScratchRepo, :create, c.user, nil, attrs(attachment(blob.id)), %{
               now: @now
             })

    [[identified]] = rows("SELECT metadata FROM active_storage_blobs WHERE id=$1", [blob.id])
    assert Jason.decode!(identified)["identified"] == true
    refute Jason.decode!(identified)["analyzed"]

    assert [[job]] =
             rows(
               "SELECT id FROM oban.oban_jobs WHERE worker='Dawarich.Trips.AnalyzeAttachmentWorker'"
             )

    [[key]] = rows("SELECT key FROM active_storage_blobs WHERE id=$1", [blob.id])
    file = Storage.disk_path(Path.join(c.root, "storage"), key)
    File.rm!(file)
    assert %{success: 0, failure: 1} = Oban.drain_queue(__MODULE__, queue: :trips)
    assert rows("SELECT state FROM oban.oban_jobs WHERE id=$1", [job]) == [["retryable"]]
    [[metadata]] = rows("SELECT metadata FROM active_storage_blobs WHERE id=$1", [blob.id])
    refute Jason.decode!(metadata)["analyzed"]
    File.write!(file, bytes)

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(__MODULE__, queue: :trips, with_scheduled: true)

    [[metadata]] = rows("SELECT metadata FROM active_storage_blobs WHERE id=$1", [blob.id])

    assert Jason.decode!(metadata) == %{
             "caption" => "Leipzig",
             "identified" => true,
             "analyzed" => true,
             "width" => 16,
             "height" => 16
           }

    assert {:ok, form} = WebForm.load(ScratchRepo, c.user, trip.id, %{})
    assert form.description =~ "representations/redirect/"
    assert form.description =~ "data-trix-attachment"
    [[composed]] = rows("SELECT metadata FROM active_storage_blobs WHERE id=$1", [blob.id])

    rows(
      "UPDATE active_storage_blobs SET checksum='synthetic',content_type='application/octet-stream',metadata=$2 WHERE id=$1",
      [
        blob.id,
        Jason.encode!(Map.put(Jason.decode!(composed), "composed", true))
      ]
    )

    assert :ok =
             Dawarich.Trips.AnalyzeAttachmentWorker.perform(%Oban.Job{
               args: %{"blob_id" => blob.id}
             })

    assert rows("SELECT content_type FROM active_storage_blobs WHERE id=$1", [blob.id]) == [
             ["application/octet-stream"]
           ]

    assert rows("SELECT kind FROM phoenix.rails_commands") == []
  end

  @tag a12f3a_t04_gallery: true
  test "T04: attachment galleries preserve source layout and preview bounds", c do
    bytes =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAEElEQVR4nGNgGAWjYBTAAAADEAABPywr7AAAAABJRU5ErkJggg=="
      )

    blob =
      Dawarich.RailsBlobFixture.create!(
        ScratchRepo,
        Path.join(c.root, "storage"),
        "auwald.png",
        bytes,
        content_type: "image/png",
        metadata: %{"identified" => true, "analyzed" => true, "width" => 16, "height" => 16}
      )

    one = String.replace(attachment(blob.id), " sgid=", " presentation=\"gallery\" sgid=")
    body = "<div>" <> one <> " " <> one <> "</div>"

    assert {:ok, trip} =
             WebWrite.run(ScratchRepo, :create, c.user, nil, attrs(body), %{now: @now})

    assert rows("SELECT count(*) FROM active_storage_attachments WHERE blob_id=$1", [blob.id]) ==
             [[1]]

    assert {:ok, rendered} = RichContent.read(body, ScratchRepo)
    assert rendered =~ "attachment-gallery attachment-gallery--2"
    assert rendered =~ "</action-text-attachment><action-text-attachment"

    [url, _] =
      rendered |> LazyHTML.from_fragment() |> LazyHTML.query("img") |> LazyHTML.attribute("src")

    variation = url |> String.split("/") |> Enum.at(6) |> URI.decode()
    assert {:ok, decoded} = Dawarich.Storage.Variation.decode(variation)
    assert decoded.transformations["resize_to_limit"] == [800, 600]
    assert {:ok, form} = WebForm.load(ScratchRepo, c.user, trip.id, %{})
    assert {:ok, canonical} = RichContent.canonical(form.description, ScratchRepo)
    assert {:ok, again} = RichContent.read(canonical, ScratchRepo)
    assert again =~ "attachment-gallery attachment-gallery--2"
  end

  defp attrs(body),
    do: %{
      "name" => "Auwald",
      "started_at" => "2026-10-03T09:00:00Z",
      "ended_at" => "2026-10-04T19:00:00Z",
      "description" => body
    }

  defp attachment(id), do: attachment_sgid(RailsMessages.attachable_sgid(id))

  defp attachment_sgid(sgid),
    do: "<action-text-attachment sgid=\"#{sgid}\"></action-text-attachment>"

  defp attach(type, record, blob, name),
    do:
      rows(
        "INSERT INTO active_storage_attachments(record_type,record_id,blob_id,name,created_at) VALUES($1,$2,$3,$4,$5)",
        [type, record, blob, name, DateTime.to_naive(@now)]
      )

  defp blob(root, type, filename) do
    key = Storage.generate_key()
    file = Storage.disk_path(Path.join(root, "storage"), key)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, "synthetic")

    [[id]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES($1,$2,$3,'{}','local',9,'synthetic',$4) RETURNING id",
        [key, filename, type, DateTime.to_naive(@now)]
      )

    {id, file}
  end
end
