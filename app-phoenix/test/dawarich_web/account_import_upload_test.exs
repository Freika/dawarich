defmodule DawarichWeb.AccountImportUploadTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{DirectUpload, Translate}

  @endpoint DawarichWeb.Endpoint
  @checksum Base.encode64(:crypto.hash(:md5, String.duplicate("z", 2048)))

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = Map.new(~w(DAWARICH_RAILS SELF_HOSTED), &{&1, System.get_env(&1)})
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      for {key, value} <- previous,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    RailsUser.insert!(%{
      id: 9894,
      email: "account-upload@dawarich.test",
      status: 1,
      subscription_source: 0,
      settings: %{"timezone" => "UTC", "locale" => "en", "onboarding_completed" => true}
    })

    Ownership.put!(Repo, "command:users.import_data", :oban)
    :ok
  end

  defp socket(attrs \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            current_user: Dawarich.Accounts.get(9894),
            locale: "en",
            base_url: "http://www.example.com",
            checksums: %{"0" => @checksum}
          },
          attrs
        )
    }
  end

  defp entry(attrs),
    do:
      struct(
        Phoenix.LiveView.UploadEntry,
        Map.merge(
          %{
            client_name: "backup.zip",
            client_size: 2048,
            client_type: "application/zip",
            ref: "0"
          },
          attrs
        )
      )

  defp blobs,
    do:
      Repo.query!("SELECT filename, byte_size, checksum, content_type FROM active_storage_blobs").rows

  defp text(key), do: Translate.t("en", key, %{})

  test "the presigner creates an owned blob with the client checksum and returns only its reference" do
    assert {:ok, meta, _socket} = DirectUpload.presign(entry(%{}), socket())

    assert meta.uploader == "Direct"
    assert Enum.sort(Map.keys(meta)) == [:upload_ref, :uploader]
    assert is_binary(Map.fetch!(meta, :upload_ref))
    assert blobs() == [["backup.zip", 2048, @checksum, "application/zip"]]

    [[blob_id]] = Repo.query!("SELECT id FROM active_storage_blobs").rows
    assert Dawarich.Storage.UploadReceipts.owned_archive?(Repo, blob_id, 9894)
  end

  test "the presigner refuses a missing checksum, a non-ZIP file and a large legacy-trial archive" do
    assert {:error, %{reason: missing}, _} =
             DirectUpload.presign(entry(%{}), socket(%{checksums: %{}}))

    assert missing ==
             text(
               "controllers.settings.users.an_error_occurred_while_starting_the_import_please_try_again"
             )

    assert {:error, %{reason: zip}, _} =
             DirectUpload.presign(
               entry(%{client_name: "notes.txt", client_type: "text/plain"}),
               socket()
             )

    assert zip == text("javascript.messages.please_select_a_valid_zip_file")

    Repo.query!("UPDATE users SET status=2, subscription_source=0 WHERE id=9894")

    assert {:error, %{reason: limit}, _} =
             DirectUpload.presign(entry(%{client_size: 11 * 1024 * 1024 + 1}), socket())

    assert limit == text("javascript.upload.file_size_limit")
    assert {:ok, _, _} = DirectUpload.presign(entry(%{client_size: 11 * 1024 * 1024}), socket())
    assert length(blobs()) == 1
  end

  defp live_as do
    session = RailsUser.session(9894)

    live(
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> RailsUser.connecting_as(9894),
      "/users/edit"
    )
  end

  defp archive(view) do
    upload =
      file_input(view, "#import-form", :archive, [
        %{name: "backup.zip", content: String.duplicate("z", 2048), type: "application/zip"}
      ])

    view |> form("#import-form") |> render_change(upload)
    upload
  end

  defp imports,
    do: Repo.query!("SELECT count(*) FROM job_outbox WHERE command_type='users.import_data'").rows

  test "a completed upload starts exactly one import with the Rails notice" do
    {:ok, view, _html} = live_as()
    upload = archive(view)
    [%{"ref" => ref}] = upload.entries

    render_hook(view, "archive_checksum", %{"ref" => ref, "checksum" => @checksum})
    assert render_upload(upload, "backup.zip") =~ "100%"
    [[key]] = Repo.query!("SELECT key FROM active_storage_blobs", [], log: false).rows
    storage = Dawarich.Imports.StorageContext.storage()
    path = Dawarich.Storage.disk_path(storage.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, String.duplicate("z", 2048))
    on_exit(fn -> File.rm(path) end)
    assert has_element?(view, "#import-form button[type=submit]:not([disabled])")

    html = view |> form("#import-form") |> render_submit()

    assert html =~
             text(
               "controllers.settings.users.your_data_import_has_been_started_you_will_receive_a"
             )

    assert imports() == [[1]]
  end

  test "checksums are kept only for the current entry and only in MD5 form" do
    {:ok, view, _html} = live_as()
    upload = archive(view)
    [%{"ref" => ref}] = upload.entries

    for n <- 1..20,
        do: render_hook(view, "archive_checksum", %{"ref" => "x#{n}", "checksum" => @checksum})

    render_hook(view, "archive_checksum", %{"ref" => ref, "checksum" => "not-a-digest"})
    render_hook(view, "archive_checksum", %{"checksum" => @checksum})
    assert Process.alive?(view.pid)
    assert :sys.get_state(view.pid).socket.assigns.checksums == %{}

    render_hook(view, "archive_checksum", %{"ref" => ref, "checksum" => @checksum})
    assert :sys.get_state(view.pid).socket.assigns.checksums == %{ref => @checksum}
  end

  test "importing without a completed upload starts nothing" do
    {:ok, view, _html} = live_as()
    assert has_element?(view, "#import-form button[type=submit][disabled]")

    render_hook(view, "import_archive", %{})
    assert imports() == [[0]]
  end

  test "a cancelled entry disappears and cannot be imported" do
    {:ok, view, _html} = live_as()
    upload = archive(view)
    [%{"ref" => ref}] = upload.entries
    render_hook(view, "archive_checksum", %{"ref" => ref, "checksum" => @checksum})
    render_upload(upload, "backup.zip", 50)
    assert upload_refs(view) == [ref]

    view |> element("#import-form [phx-click='cancel_archive']") |> render_click(%{"ref" => ref})

    assert upload_refs(view) == []
    render_hook(view, "import_archive", %{})
    assert imports() == [[0]]
  end

  defp upload_refs(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#import-form [data-entry-ref]")
    |> LazyHTML.attribute("data-entry-ref")
  end

  test "account cancellation cleans its pending object while a completed owned archive imports once" do
    user = Dawarich.Accounts.get(9894)
    scope = Dawarich.Accounts.Scope.for_user(user, "en")
    bytes = "owned-account-archive"
    checksum = Base.encode64(:crypto.hash(:md5, bytes))

    {:ok, cancelled, _} =
      DirectUpload.presign(
        entry(%{client_size: byte_size(bytes)}),
        socket(%{checksums: %{"0" => checksum}})
      )

    ref = Map.fetch!(cancelled, :upload_ref)

    [[blob, key]] =
      Repo.query!(
        "SELECT b.id,b.key FROM active_storage_blobs b JOIN phoenix.native_uploads u ON u.blob_id=b.id WHERE u.reference=$1",
        [ref],
        log: false
      ).rows

    storage = Dawarich.Imports.StorageContext.storage()
    path = Dawarich.Storage.disk_path(storage.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)
    on_exit(fn -> File.rm(path) end)
    assert {:ok, :cancelled} = Dawarich.Uploads.cancel(scope, ref)
    assert :ok = Dawarich.Uploads.CleanupWorker.run(%{"reference" => ref}, repo: Repo)
    refute File.exists?(path)

    assert [] =
             Repo.query!("SELECT id FROM active_storage_blobs WHERE id=$1", [blob], log: false).rows

    assert {:error, _} = apply(Dawarich.UserData, :start_upload, [scope, ref])

    {:ok, accepted, _} =
      DirectUpload.presign(
        entry(%{client_size: byte_size(bytes)}),
        socket(%{checksums: %{"0" => checksum}})
      )

    accepted_ref = Map.fetch!(accepted, :upload_ref)

    [[key]] =
      Repo.query!(
        "SELECT b.key FROM active_storage_blobs b JOIN phoenix.native_uploads u ON u.blob_id=b.id WHERE u.reference=$1",
        [accepted_ref],
        log: false
      ).rows

    path = Dawarich.Storage.disk_path(storage.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)
    on_exit(fn -> File.rm(path) end)
    assert :ok = apply(Dawarich.UserData, :start_upload, [scope, accepted_ref])
    assert {:error, :claimed} = apply(Dawarich.UserData, :start_upload, [scope, accepted_ref])
    assert imports() == [[1]]
    assert File.exists?(path)
  end

  test "upload failures distinguish checksum preparation authorization storage and timeout without echoing inputs" do
    {:ok, view, _} = live_as()

    for stage <- ~w(checksum preparation target upload timeout) do
      html =
        render_hook(view, "upload_preparation_error", %{
          "stage" => stage,
          "error" => "untrusted-private-error"
        })

      assert html =~ text("native_upload." <> stage)
      refute html =~ "untrusted-private-error"
    end

    before = render(view)
    render_hook(view, "upload_preparation_error", %{"stage" => "forged-stage"})
    assert render(view) == before
  end

  test "account upload principals contain no key or password hash before and after rotation" do
    {:ok, view, _} = live_as()

    for principal <- [
          :sys.get_state(view.pid).socket.assigns.current_user,
          :sys.get_state(view.pid).socket.assigns.profile_user,
          :sys.get_state(view.pid).socket.assigns.current_scope.user
        ] do
      refute Map.has_key?(principal, :api_key)
      refute Map.has_key?(principal, :encrypted_password)
    end

    render_hook(view, "rotate_api_key", %{})
    current = :sys.get_state(view.pid).socket.assigns.current_user
    refute Map.has_key?(current, :api_key)
    refute Map.has_key?(current, :encrypted_password)
    assert is_binary(current.session_version)
  end
end
