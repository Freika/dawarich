defmodule Dawarich.NativeAccountCommandsTest do
  use Dawarich.DataCase, async: false
  alias Dawarich.Accounts.{Principal, Scope}
  alias Dawarich.{Uploads, UserData, Storage}
  alias Dawarich.Jobs.Ownership

  setup do
    previous_mode = System.get_env("DAWARICH_RAILS")
    previous_storage = Application.fetch_env(:dawarich, :imports_storage)
    System.put_env("DAWARICH_RAILS", "on")
    root = Path.join(System.tmp_dir!(), "native-account-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    storage = %{service: "local", root: root}
    Application.put_env(:dawarich, :imports_storage, storage)

    on_exit(fn ->
      if previous_mode,
        do: System.put_env("DAWARICH_RAILS", previous_mode),
        else: System.delete_env("DAWARICH_RAILS")

      case previous_storage do
        {:ok, value} -> Application.put_env(:dawarich, :imports_storage, value)
        :error -> Application.delete_env(:dawarich, :imports_storage)
      end

      File.rm_rf!(root)
    end)

    user =
      Dawarich.Test.RailsUser.insert!(%{
        id: 13231,
        email: "native-account@example.invalid",
        settings: %{"timezone" => "UTC"}
      })

    for key <- ~w(command:users.import_data command:users.export_data),
        do: Ownership.put!(Repo, key, :oban)

    %{scope: Scope.for_user(Principal.project(user), "en"), storage: storage}
  end

  test "native account import refuses unavailable ownership without claim attachment or Rails command",
       c do
    ref = upload(c)
    before = footprint()
    Ownership.put!(Repo, "command:users.import_data", :sidekiq)
    assert {:error, :not_owned} = UserData.start_upload(c.scope, ref)
    assert footprint() == before

    assert [["pending"]] ==
             rows("SELECT state FROM phoenix.native_uploads WHERE reference=$1", [ref])
  end

  test "native account backup refuses unavailable ownership in place without Rails command", c do
    before = footprint()
    Ownership.put!(Repo, "command:users.export_data", :sidekiq)
    {:noreply, socket} = backup(c.scope)
    assert footprint() == before
    assert socket.redirected == nil
    assert socket.assigns.flash["error"] || socket.assigns.flash["alert"]
  end

  test "standalone account controls publish native work despite legacy Sidekiq owner rows", c do
    System.put_env("DAWARICH_RAILS", "off")

    for key <- ~w(command:users.import_data command:users.export_data),
        do: Ownership.put!(Repo, key, :sidekiq)

    assert :ok = UserData.start_upload(c.scope, upload(c))
    {:noreply, socket} = backup(c.scope)
    assert socket.redirected == {:redirect, %{to: "/exports", status: 302}}
    assert [] == rows("SELECT kind FROM phoenix.rails_commands")

    assert [["users.export_data"], ["users.import_data"]] ==
             rows("SELECT command_type FROM job_outbox ORDER BY command_type")
  end

  test "native account controls refuse a revoked original identity without effects", c do
    ref = upload(c)

    rows("UPDATE users SET encrypted_password='revoked-native-account' WHERE id=$1", [
      c.scope.user.id
    ])

    before = footprint()
    assert {:error, :stale_session} = UserData.start_upload(c.scope, ref)
    {:noreply, socket} = backup(c.scope)
    assert socket.redirected == {:redirect, %{to: "/users/sign_in", status: 302}}
    assert footprint() == before

    assert [["pending"]] ==
             rows("SELECT state FROM phoenix.native_uploads WHERE reference=$1", [ref])
  end

  test "native backup re-admits the original identity after holding producer ownership", c do
    before = footprint()

    result =
      apply(UserData, :request_native_export, [
        c.scope,
        [
          after_owner_lock: fn repo ->
            assert repo.in_transaction?()

            repo.query!(
              "UPDATE users SET encrypted_password='revoked-at-producer-lock' WHERE id=$1",
              [c.scope.user.id], log: false)
          end
        ]
      ])

    assert result == {:error, :stale_session}
    assert footprint() == before
  end

  defp backup(scope) do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}, current_user: scope.user, locale: scope.locale}
    }

    DawarichWeb.AccountLive.Edit.handle_event("export_data", %{}, socket)
  end

  defp upload(c) do
    bytes = "synthetic-account-zip"

    attrs = %{
      filename: "backup.zip",
      byte_size: byte_size(bytes),
      checksum: Base.encode64(:crypto.hash(:md5, bytes)),
      content_type: "application/zip"
    }

    assert {:ok, ref} = Uploads.reserve(c.scope, attrs, %{storage: c.storage, kind: :account})

    [[key]] =
      rows(
        "SELECT b.key FROM active_storage_blobs b JOIN phoenix.native_uploads u ON u.blob_id=b.id WHERE u.reference=$1",
        [ref]
      )

    path = Storage.disk_path(c.storage.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)
    ref
  end

  defp footprint do
    for table <- ~w(imports exports active_storage_attachments job_outbox phoenix.rails_commands),
        into: %{},
        do: {table, rows("SELECT count(*) FROM " <> table)}
  end
end
