defmodule DawarichWeb.ImportsLiveUploadTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Repo, Storage, Uploads}
  alias Dawarich.Test.{RailsUser, ImportsExportsSeeds}
  @endpoint DawarichWeb.Endpoint
  @bytes "<gpx/>"
  @checksum Base.encode64(:crypto.hash(:md5, @bytes))

  setup do
    user =
      RailsUser.insert!(%{
        id: 11061,
        email: "batch-upload@example.invalid",
        settings: %{"timezone" => "UTC", "onboarding_completed" => true}
      })

    for command <- ~w(imports.process_gpx imports.process_normal),
        do: Dawarich.Jobs.Ownership.put!(Repo, "command:" <> command, :oban)

    %{user: user}
  end

  defp live_as(user),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), "/imports/new")

  defp select(view, names) do
    upload =
      file_input(
        view,
        "#phx-import-upload",
        :files,
        for(name <- names, do: %{name: name, content: @bytes, type: "application/gpx+xml"})
      )

    view |> form("#phx-import-upload") |> render_change(upload)

    for entry <- upload.entries,
        do:
          render_hook(view, "archive_checksum", %{"ref" => entry["ref"], "checksum" => @checksum})

    upload
  end

  defp store(name) do
    [[key]] =
      Repo.query!("SELECT key FROM active_storage_blobs WHERE filename=$1", [name], log: false).rows

    config = Dawarich.Imports.StorageContext.storage()
    path = Storage.disk_path(config.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, @bytes)
    on_exit(fn -> File.rm(path) end)
  end

  defp count(table), do: Repo.query!("SELECT count(*) FROM " <> table, [], log: false).rows

  test "only a fully completed authorized upload batch starts imports", c do
    {:ok, view, _} = live_as(c.user)

    refute has_element?(
             view,
             "[data-controller], [data-action], turbo-frame, [phx-hook=RailsStimulus]"
           )

    upload = select(view, ~w(first.gpx second.gpx))
    render_upload(upload, "first.gpx")
    render_upload(upload, "second.gpx", 50)
    store("first.gpx")
    render_hook(view, "start_imports", %{})
    assert count("imports") == [[0]]
    render_upload(upload, "second.gpx", 50)
    render_hook(view, "start_imports", %{})
    assert count("imports") == [[0]]
    assert count("active_storage_attachments") == [[0]]
    assert has_element?(view, "[role=alert]")
    store("second.gpx")
    render_hook(view, "start_imports", %{})
    assert_redirect(view, "/imports")
    assert count("imports") == [[2]]
    assert count("active_storage_attachments") == [[2]]
  end

  test "trial batch and size limits are rechecked after another tab consumes quota", c do
    {:ok, view, _} = live_as(c.user)
    upload = select(view, ~w(trial.gpx))
    render_upload(upload, "trial.gpx")
    store("trial.gpx")

    Repo.query!("UPDATE users SET status=2,subscription_source=0 WHERE id=$1", [c.user.id],
      log: false
    )

    for id <- 110_610..110_614,
        do:
          ImportsExportsSeeds.import!(%{
            id: id,
            user_id: c.user.id,
            name: "other-#{id}.gpx",
            demo: false
          })

    render_hook(view, "start_imports", %{})
    assert count("imports") == [[5]]
    assert count("active_storage_attachments") == [[0]]
    assert has_element?(view, "[role=alert]")
    Repo.query!("DELETE FROM imports WHERE user_id=$1", [c.user.id], log: false)

    Repo.query!(
      "UPDATE phoenix.native_uploads SET original_size=$1 WHERE user_id=$2",
      [11 * 1024 * 1024 + 1, c.user.id],
      log: false
    )

    render_hook(view, "start_imports", %{})
    assert count("imports") == [[0]]
    assert count("active_storage_attachments") == [[0]]
  end

  test "cancel and disconnect clean pending files and preserve accepted imports", c do
    {:ok, view, _} = live_as(c.user)
    upload = select(view, ~w(cancel.gpx))
    render_upload(upload, "cancel.gpx", 50)
    store("cancel.gpx")
    [entry] = upload.entries
    ref = :sys.get_state(view.pid).socket.assigns.upload_refs[entry["ref"]]
    render_hook(view, "cancel_upload", %{"ref" => entry["ref"]})
    assert :ok = Uploads.CleanupWorker.run(%{"reference" => ref}, repo: Repo)
    assert count("active_storage_blobs") == [[0]]
    upload = select(view, ~w(accepted.gpx))
    render_upload(upload, "accepted.gpx")
    store("accepted.gpx")
    [entry] = upload.entries
    ref = :sys.get_state(view.pid).socket.assigns.upload_refs[entry["ref"]]
    scope = :sys.get_state(view.pid).socket.assigns.current_scope
    render_hook(view, "start_imports", %{})
    assert_redirect(view, "/imports")
    assert {:error, :claimed} = Uploads.cancel(scope, ref)
    assert :ok = Uploads.CleanupWorker.run(%{"reference" => ref}, repo: Repo)
    assert count("active_storage_blobs") == [[1]]
    assert count("active_storage_attachments") == [[1]]
  end
end
