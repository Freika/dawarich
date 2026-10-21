defmodule Dawarich.Integrations.TrekTest do
  use ExUnit.Case, async: false
  alias Dawarich.{Accounts, ActiveRecordEncryption, Repo}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Integrations.Trek
  alias Dawarich.Test.RailsUser

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    user =
      RailsUser.insert!(%{
        id: 8591,
        email: "native-trek-context@dawarich.test",
        settings: %{"timezone" => "UTC"}
      })

    %{
      scope: Scope.for_user(Accounts.get(user.id), "en"),
      url: Dawarich.Test.NativeIntegrationStub.start!()
    }
  end

  defp connect(c),
    do: Trek.create_source(c.scope, %{"base_url" => c.url, "api_key" => "synthetic-trek"})

  defp rows(sql, args), do: Repo.query!(sql, args, log: false).rows
  defp own(kind), do: Dawarich.Jobs.Ownership.put!(Repo, "command:" <> kind, :oban)

  test "create verifies encrypts reconnects and preserves an active import claim", c do
    assert {:ok, id} = connect(c)
    [[encrypted]] = rows("SELECT api_key FROM trip_sources WHERE id=$1", [id])
    {:ok, key} = ActiveRecordEncryption.key()
    assert {:ok, "synthetic-trek"} = ActiveRecordEncryption.decrypt(encrypted, key)
    rows("UPDATE trip_sources SET status=1 WHERE id=$1", [id])
    assert {:ok, ^id} = connect(c)
    rows("UPDATE trip_sources SET importing=true WHERE id=$1", [id])
    assert {:error, :importing} = connect(c)
    assert rows("SELECT count(*) FROM trip_sources WHERE user_id=$1", [c.scope.user.id]) == [[1]]
  end

  test "list and import filter dated active identifiers and claim the durable job once", c do
    {:ok, id} = connect(c)
    own("imports.trek_import")
    assert {:ok, %{trips: trips, selected: []}} = Trek.list_trips(c.scope, id)
    assert length(trips) == 3

    assert {:ok, :syncing} =
             Trek.import_trips(c.scope, id, [
               "dated",
               "dated",
               "",
               "unknown",
               "archived",
               "undated"
             ])

    [[payload]] = rows("SELECT payload FROM job_outbox WHERE aggregate_id=$1", [id])
    assert payload["identifiers"] == ["dated"]
    assert {:error, :importing} = Trek.import_trips(c.scope, id, ["dated"])
    assert rows("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]) == [[1]]
  end

  test "manual sync refuses disabled and importing; clear rotates token; delete keeps trip data",
       c do
    {:ok, id} = connect(c)
    own("imports.trek_sync")
    assert {:ok, _} = Trek.sync_source(c.scope, id)
    rows("UPDATE trip_sources SET status=1 WHERE id=$1", [id])
    assert {:error, :disabled} = Trek.sync_source(c.scope, id)
    rows("UPDATE trip_sources SET status=0,importing=true WHERE id=$1", [id])
    assert {:error, :importing} = Trek.sync_source(c.scope, id)
    rows("UPDATE trip_sources SET importing=false,selection_token='original' WHERE id=$1", [id])

    rows(
      "INSERT INTO trips(user_id,name,started_at,ended_at,trip_source_id,source_identifier,source_status,created_at,updated_at) VALUES($1,'Kept','2030-01-01','2030-01-02',$2,'dated',0,now(),now())",
      [c.scope.user.id, id]
    )

    assert {:ok, :empty} = Trek.import_trips(c.scope, id, [])

    assert rows("SELECT selection_token <> 'original' FROM trip_sources WHERE id=$1", [id]) == [
             [true]
           ]

    assert {:ok, _} = Trek.delete_source(c.scope, id)

    assert rows("SELECT name,trip_source_id,source_status FROM trips WHERE user_id=$1", [
             c.scope.user.id
           ]) == [["Kept", nil, 1]]
  end

  test "foreign malformed and HTML ids change nothing and inactive or Lite scopes are refused",
       c do
    {:ok, id} = connect(c)
    other = RailsUser.insert!(%{id: 8592, email: "native-trek-other@dawarich.test"})
    scope = Scope.for_user(Accounts.get(other.id), "en")

    for bad <- [id, "bad", "#{id}.html"] do
      assert {:error, :not_found} = Trek.list_trips(scope, bad)
      assert {:error, :not_found} = Trek.sync_source(scope, bad)
      assert {:error, :not_found} = Trek.import_trips(scope, bad, [])
      assert {:error, :not_found} = Trek.delete_source(scope, bad)
    end

    rows("UPDATE users SET active_until=now()-interval '1 day' WHERE id=$1", [c.scope.user.id])
    assert {:error, :inactive} = connect(c)
    rows("UPDATE users SET active_until='3026-01-01',plan=0 WHERE id=$1", [c.scope.user.id])
    System.put_env("SELF_HOSTED", "false")
    assert {:error, :pro_required} = Trek.delete_source(c.scope, id)
    assert rows("SELECT id FROM trip_sources WHERE id=$1", [id]) == [[id]]
  end
end
