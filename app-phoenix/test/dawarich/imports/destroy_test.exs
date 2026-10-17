defmodule Dawarich.Imports.DestroyTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.Destroy
  alias Dawarich.Jobs.Ownership

  setup do
    [[user], [other]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES('destroy@example.test',now(),now()),('other-destroy@example.test',now(),now()) RETURNING id"
      )

    [[id]] =
      rows(
        "INSERT INTO imports(user_id,name,source,status,created_at,updated_at) VALUES($1,'destroy.gpx',4,2,now(),now()) RETURNING id",
        [user]
      )

    Ownership.put!(Dawarich.ScratchRepo, "command:imports.destroy", :oban)

    %{
      user: user,
      other: other,
      id: id,
      context: %{zone: "UTC", locale: "en", now: DateTime.utc_now()}
    }
  end

  test "enqueues one canonical command and marks deleting atomically", %{
    user: user,
    id: id,
    context: context
  } do
    assert {:ok, :queued} = Destroy.enqueue(Dawarich.ScratchRepo, user, id, context)
    assert [[4]] = rows("SELECT status FROM imports WHERE id=$1", [id])

    assert [["imports.destroy", 1, %{"import_id" => ^id, "user_id" => ^user}]] =
             rows("SELECT command_type,command_version,payload FROM job_outbox")

    assert {:ok, :queued} = Destroy.enqueue(Dawarich.ScratchRepo, user, id, context)
    assert [[1]] = rows("SELECT count(*) FROM job_outbox")
  end

  test "foreign and deleted users cannot change or enqueue an import", %{
    user: user,
    other: other,
    id: id,
    context: context
  } do
    assert {:error, :not_found} = Destroy.enqueue(Dawarich.ScratchRepo, other, id, context)
    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [user])
    assert {:error, :not_found} = Destroy.enqueue(Dawarich.ScratchRepo, user, id, context)
    assert [[2]] = rows("SELECT status FROM imports WHERE id=$1", [id])
    assert [] = rows("SELECT event_id FROM job_outbox")
  end

  test "corrupt foreign-user children are refused before marking deleting", %{
    user: user,
    other: other,
    id: id,
    context: context
  } do
    rows(
      "INSERT INTO points(user_id,import_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,1,ST_SetSRID(ST_MakePoint(10,50),4326)::geography,now(),now())",
      [other, id]
    )

    assert {:error, :not_found} = Destroy.enqueue(Dawarich.ScratchRepo, user, id, context)
    assert [[2]] = rows("SELECT status FROM imports WHERE id=$1", [id])
    assert [] = rows("SELECT event_id FROM job_outbox")
  end

  test "Sidekiq owner gets a durable reverse producer without native outbox", %{
    user: user,
    id: id,
    context: context
  } do
    Ownership.put!(Dawarich.ScratchRepo, "command:imports.destroy", :sidekiq)
    assert {:ok, :queued} = Destroy.enqueue(Dawarich.ScratchRepo, user, id, context)
    assert [[4]] = rows("SELECT status FROM imports WHERE id=$1", [id])

    assert [["imports.destroy_requested", %{"import_id" => ^id, "user_id" => ^user}]] =
             rows("SELECT kind,payload FROM phoenix.rails_commands")

    assert [] = rows("SELECT event_id FROM job_outbox")
  end
end
