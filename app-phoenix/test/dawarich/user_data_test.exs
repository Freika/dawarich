defmodule Dawarich.UserDataTest do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Accounts.Scope
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.RailsUser
  alias Dawarich.UserData

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    RailsUser.insert!(%{
      id: 9892,
      email: "user-data-context@example.invalid",
      status: 1,
      subscription_source: 0,
      settings: %{"timezone" => "Europe/Berlin", "locale" => "de"}
    })

    Ownership.put!(Repo, "command:users.export_data", :oban)
    Ownership.put!(Repo, "command:users.import_data", :oban)
    %{scope: Scope.for_user(Dawarich.Accounts.get(9892), "de"), root: dir}
  end

  defp blob(c, name),
    do:
      Dawarich.RailsBlobFixture.create!(Repo, c.root, name, "synthetic ZIP",
        content_type: "application/zip",
        user_id: 9892
      )

  defp outbox(type),
    do:
      Repo.query!("SELECT payload FROM job_outbox WHERE command_type=$1", [type]).rows
      |> Enum.map(&hd/1)

  test "an export request queues one export with the user's zone and locale", %{scope: scope} do
    assert :ok = UserData.request_export(scope)

    assert outbox("users.export_data") == [
             %{"user_id" => 9892, "time_zone" => "Europe/Berlin", "locale" => "de"}
           ]
  end

  test "an import starts from an owned ZIP archive and queues one import", c do
    file = blob(c, "backup.zip")

    assert :ok = UserData.start_import(c.scope, file.signed_id)

    assert [[import_id, "backup.zip", 8]] =
             Repo.query!("SELECT id, name, source FROM imports WHERE user_id=9892").rows

    assert [%{"import_id" => ^import_id, "user_id" => 9892, "locale" => "de"}] =
             outbox("users.import_data")
  end

  test "a blank, unknown or non-ZIP archive is refused without effects", c do
    assert {:error, :blank} = UserData.start_import(c.scope, "")
    assert {:error, :invalid_archive} = UserData.start_import(c.scope, "not-a-signed-id")

    text =
      Dawarich.RailsBlobFixture.create!(Repo, c.root, "notes.txt", "plain",
        content_type: "text/plain",
        user_id: 9892
      )

    assert {:error, :invalid_archive} = UserData.start_import(c.scope, text.signed_id)
    assert Repo.query!("SELECT count(*) FROM imports").rows == [[0]]
    assert outbox("users.import_data") == []
  end

  test "a legacy trial over 11 MB is refused with the validation outcome", c do
    Repo.query!("UPDATE users SET status=2, subscription_source=0 WHERE id=9892")
    file = blob(c, "big.zip")

    Repo.query!("UPDATE active_storage_blobs SET byte_size=$1 WHERE id=$2", [
      11 * 1024 * 1024 + 1,
      file.id
    ])

    assert {:error, :validation} = UserData.start_import(c.scope, file.signed_id)
    assert Repo.query!("SELECT count(*) FROM imports").rows == [[0]]
  end
end
