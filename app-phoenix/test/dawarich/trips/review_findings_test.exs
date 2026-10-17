defmodule Dawarich.Trips.ReviewFindingsTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.{RailsBlobFixture, RailsMessages}
  alias Dawarich.Trips.{WebWrite, WebDelete, RichContent, AnalyzeAttachmentWorker}
  @now ~U[2026-10-03 10:00:00.000000Z]
  setup do
    root = Path.join(System.tmp_dir!(), "trip-review-" <> Ecto.UUID.generate())
    old_root = Application.fetch_env!(:dawarich, :rails_root)
    old_repo = Application.get_env(:dawarich, :jobs_repo)
    File.mkdir_p!(Path.join(root, "public"))
    File.cp!(Path.join(old_root, "public/404.html"), Path.join(root, "public/404.html"))
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
      Dawarich.Test.RailsUser.insert!(
        %{
          id: 980_440,
          api_key: "",
          email: "trip-review@example.test",
          settings: %{"timezone" => "UTC"}
        },
        ScratchRepo
      )

    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:trips.calculate", :oban)
    %{root: Path.join(root, "storage"), user: user}
  end

  @tag review_r1: true
  test "R1: trip purge removes preview graph storage-first and revokes capabilities while preserving shared variants",
       c do
    for shared <- [false, true] do
      parent = blob(c.root, "doc.pdf", "%PDF-1.4\n", "application/pdf")
      preview = blob(c.root, "preview.png", "synthetic", "image/png")
      variant = blob(c.root, "variant.png", "synthetic", "image/png")
      attach("ActiveStorage::Blob", parent.id, preview.id, "preview_image")

      [[v]] =
        rows(
          "INSERT INTO active_storage_variant_records(blob_id,variation_digest) VALUES($1,$2) RETURNING id",
          [preview.id, Ecto.UUID.generate()]
        )

      attach("ActiveStorage::VariantRecord", v, variant.id, "image")
      if shared, do: attach("Legacy::Owner", c.user.id, variant.id, "shared")
      ids = [parent.id, preview.id, variant.id]

      files =
        Map.new(rows("SELECT id,key FROM active_storage_blobs WHERE id=ANY($1)", [ids]), fn [
                                                                                              id,
                                                                                              key
                                                                                            ] ->
          {id, Dawarich.Storage.disk_path(c.root, key)}
        end)

      assert {:ok, trip} =
               WebWrite.run(ScratchRepo, :create, c.user, nil, attrs(attachment(parent.id)), %{
                 now: @now
               })

      for id <- ids, do: assert(signed_status(id, c.root) == 200)
      assert {:ok, :deleted} = WebDelete.run(ScratchRepo, c.user, trip.id, %{})
      purge_ids = if shared, do: [parent.id, preview.id], else: ids

      for id <- purge_ids,
          do:
            assert(
              Dawarich.Trips.Attachments.resolve(ScratchRepo, RailsMessages.attachable_sgid(id)) ==
                :pending
            )

      for id <- purge_ids, do: assert(signed_status(id, c.root) == 404)
      File.rm!(files[preview.id])
      File.mkdir!(files[preview.id])
      assert %{success: 0, failure: 1} = Oban.drain_queue(__MODULE__, queue: :exports)

      assert rows("SELECT id FROM active_storage_blobs WHERE id=ANY($1) ORDER BY id", [ids]) ==
               Enum.map(Enum.sort(ids), &[&1])

      assert rows(
               "SELECT blob_id FROM active_storage_attachments WHERE record_type='ActiveStorage::Blob' AND record_id=$1",
               [parent.id]
             ) == [[preview.id]]

      assert rows(
               "SELECT blob_id FROM active_storage_attachments WHERE record_type='ActiveStorage::VariantRecord' AND record_id=$1",
               [v]
             ) == [[variant.id]]

      assert File.exists?(files[variant.id])
      File.rmdir!(files[preview.id])
      File.write!(files[preview.id], "synthetic")

      assert %{success: 1, failure: 0} =
               Oban.drain_queue(__MODULE__, queue: :exports, with_scheduled: true)

      for id <- purge_ids do
        refute File.exists?(files[id])
        assert signed_status(id, c.root) == 404

        assert Dawarich.Trips.Attachments.resolve(ScratchRepo, RailsMessages.attachable_sgid(id)) ==
                 :missing
      end

      assert rows("SELECT id FROM active_storage_variant_records WHERE id=$1", [v]) == []

      assert rows(
               "SELECT blob_id FROM active_storage_attachments WHERE record_type IN ('ActiveStorage::Blob','ActiveStorage::VariantRecord') AND blob_id=ANY($1)",
               [ids]
             ) == []

      if shared do
        assert File.exists?(files[variant.id])
        assert signed_status(variant.id, c.root) == 200

        assert {:ok, _} =
                 Dawarich.Trips.Attachments.resolve(
                   ScratchRepo,
                   RailsMessages.attachable_sgid(variant.id)
                 )

        assert rows("SELECT name FROM active_storage_attachments WHERE blob_id=$1", [variant.id]) ==
                 [["shared"]]
      end
    end
  end

  @tag review_r2: true
  test "R2: empty and nil descriptions retain embeds until a nonempty replacement", c do
    blob = blob(c.root, "file.txt", "synthetic", "text/plain")

    assert {:ok, trip} =
             WebWrite.run(ScratchRepo, :create, c.user, nil, attrs(attachment(blob.id)), %{
               now: @now
             })

    for body <- ["", nil] do
      assert {:ok, _} =
               WebWrite.run(ScratchRepo, :update, c.user, trip.id, %{"description" => body}, %{
                 now: @now
               })

      assert rows("SELECT blob_id FROM active_storage_attachments WHERE blob_id=$1", [blob.id]) ==
               [[blob.id]]

      assert rows(
               "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker'"
             ) == [[0]]

      assert {:ok, _} =
               Dawarich.Trips.Attachments.resolve(
                 ScratchRepo,
                 RailsMessages.attachable_sgid(blob.id)
               )
    end

    assert {:ok, _} =
             WebWrite.run(
               ScratchRepo,
               :update,
               c.user,
               trip.id,
               %{"description" => "<div><br></div>"},
               %{now: @now}
             )

    assert rows("SELECT blob_id FROM active_storage_attachments WHERE blob_id=$1", [blob.id]) ==
             []

    assert %{success: 1, failure: 0} = Oban.drain_queue(__MODULE__, queue: :exports)
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob.id]) == []
  end

  @tag review_r5: true
  test "R5: disabled image analysis publishes NullAnalyzer metadata inline without reading storage",
       c do
    bytes =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAEElEQVR4nGNgGAWjYBTAAAADEAABPywr7AAAAABJRU5ErkJggg=="
      )

    blob = blob(c.root, "square.png", bytes, "image/png")

    assert {:ok, trip} =
             WebWrite.run(ScratchRepo, :create, c.user, nil, attrs(attachment(blob.id)), %{
               now: @now
             })

    [[meta]] = rows("SELECT metadata FROM active_storage_blobs WHERE id=$1", [blob.id])
    assert Jason.decode!(meta) == %{"identified" => true, "analyzed" => true}

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Trips.AnalyzeAttachmentWorker'"
           ) == [[0]]

    [[key]] = rows("SELECT key FROM active_storage_blobs WHERE id=$1", [blob.id])
    File.rm!(Dawarich.Storage.disk_path(c.root, key))
    assert :ok = AnalyzeAttachmentWorker.perform(%Oban.Job{args: %{"blob_id" => blob.id}})
    [[meta]] = rows("SELECT metadata FROM active_storage_blobs WHERE id=$1", [blob.id])
    assert Jason.decode!(meta) == %{"identified" => true, "analyzed" => true}
    assert {:ok, form} = Dawarich.Trips.WebForm.load(ScratchRepo, c.user, trip.id, %{})

    [json] =
      form.description |> LazyHTML.from_fragment() |> LazyHTML.attribute("data-trix-attachment")

    refute Map.has_key?(Jason.decode!(json), "width")
    refute Map.has_key?(Jason.decode!(json), "height")
  end

  @tag review_r4: true
  test "R4: PDF identification sniffs binary extensions before trusting declarations", c do
    for {filename, type, bytes} <- [
          {"attachment.bin", "application/octet-stream", "%PDF-1.4\nsynthetic\n"},
          {"wrong.png", "image/png", "%PDF-1.4\nsynthetic\n"},
          {"attachment.bin", "application/octet-stream", <<239, 187, 191>> <> "%PDF-1.4\n"}
        ] do
      blob = RailsBlobFixture.create!(ScratchRepo, c.root, filename, bytes, content_type: type)

      assert {:ok, _} =
               WebWrite.run(ScratchRepo, :create, c.user, nil, attrs(attachment(blob.id)), %{
                 now: @now
               })

      assert rows("SELECT content_type FROM active_storage_blobs WHERE id=$1", [blob.id]) == [
               ["application/pdf"]
             ]

      [[metadata]] = rows("SELECT metadata FROM active_storage_blobs WHERE id=$1", [blob.id])
      assert Jason.decode!(metadata)["identified"]
    end
  end

  @tag review_r6: true
  test "R6: Trix dimensions and filesize match Ruby integer base and whitespace conversion", _c do
    for {width, expected} <- [
          {"016", 14},
          {"0x10", 16},
          {" 16 ", 16},
          {"0b10000", 16},
          {"0o20", 16},
          {"0d16", 16},
          {"+0X10", 16},
          {"-016", -14},
          {"1_024", 1024},
          {"08", nil},
          {"16.0", nil},
          {"1__6", nil}
        ] do
      body =
        "<action-text-attachment content-type=\"image/png\" url=\"https://example.test/a.png\" width=\"#{width}\" height=\"#{width}\" filesize=\"#{width}\"></action-text-attachment>"

      assert {:ok, editor} = RichContent.editor(body, ScratchRepo)
      [json] = editor |> LazyHTML.from_fragment() |> LazyHTML.attribute("data-trix-attachment")
      data = Jason.decode!(json)
      assert data["width"] == expected
      assert data["height"] == expected
      assert data["filesize"] == (expected || width)
    end
  end

  @tag review_r3: true
  test "R3: dependent destroy retains unrecognized attachment names on the description", c do
    legacy = blob(c.root, "legacy.txt", "synthetic", "text/plain")

    assert {:ok, trip} =
             WebWrite.run(ScratchRepo, :create, c.user, nil, attrs("<div>Review</div>"), %{
               now: @now
             })

    [[rich]] =
      rows("SELECT id FROM action_text_rich_texts WHERE record_type='Trip' AND record_id=$1", [
        trip.id
      ])

    rows(
      "INSERT INTO active_storage_attachments(record_type,record_id,blob_id,name,created_at) VALUES('ActionText::RichText',$1,$2,'legacy_extra',$3)",
      [rich, legacy.id, DateTime.to_naive(@now)]
    )

    assert {:ok, :deleted} = WebDelete.run(ScratchRepo, c.user, trip.id, %{})

    assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker'") ==
             [[0]]

    assert %{success: 0, failure: 0} = Oban.drain_queue(__MODULE__, queue: :exports)
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [legacy.id]) == [[legacy.id]]

    assert rows("SELECT name FROM active_storage_attachments WHERE blob_id=$1", [legacy.id]) == [
             ["legacy_extra"]
           ]
  end

  defp signed_status(id, root) do
    previous = Dawarich.Repo.get_dynamic_repo()
    Dawarich.Repo.put_dynamic_repo(ScratchRepo)

    try do
      token = RailsMessages.blob_id(id)
      conn = Plug.Test.conn(:get, "/rails/active_storage/blobs/proxy/" <> token <> "/file")
      conn = %{conn | path_params: %{"signed_id" => token}}

      DawarichWeb.ActiveStorage.Proxy.call(conn,
        storage: %{default: "local", services: %{"local" => %{service: "local", root: root}}}
      ).status
    after
      Dawarich.Repo.put_dynamic_repo(previous)
    end
  end

  defp attach(type, record, blob, name),
    do:
      rows(
        "INSERT INTO active_storage_attachments(record_type,record_id,blob_id,name,created_at) VALUES($1,$2,$3,$4,$5)",
        [type, record, blob, name, DateTime.to_naive(@now)]
      )

  defp blob(root, name, bytes, type),
    do:
      RailsBlobFixture.create!(ScratchRepo, root, name, bytes,
        content_type: type,
        metadata: %{"identified" => true}
      )

  defp attachment(id),
    do:
      "<action-text-attachment sgid=\"#{RailsMessages.attachable_sgid(id)}\"></action-text-attachment>"

  defp attrs(body),
    do: %{
      "name" => "Review",
      "started_at" => "2026-10-03T09:00:00Z",
      "ended_at" => "2026-10-04T19:00:00Z",
      "description" => body
    }
end
