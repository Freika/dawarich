defmodule Dawarich.ExportsContextTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db
  alias Dawarich.Exports
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.RailsUser

  setup do
    user =
      RailsUser.insert!(
        %{id: 11081, email: "exports-owner@example.invalid", settings: %{"timezone" => "UTC"}},
        ScratchRepo
      )

    other = RailsUser.insert!(%{id: 11082, email: "exports-other@example.invalid"}, ScratchRepo)
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:exports.points", :oban)

    %{
      scope: Scope.for_user(Dawarich.Accounts.Principal.project(user), "en"),
      other: Scope.for_user(Dawarich.Accounts.Principal.project(other), "en"),
      opts: [repo: ScratchRepo]
    }
  end

  defp params,
    do: %{"file_format" => "json", "start_at" => "2026-01-01", "end_at" => "2026-01-02"}

  defp request(c), do: apply(Exports, :request, [c.scope, params(), c.opts])

  defp events,
    do:
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Exports.EventsWorker' ORDER BY id"
      )
      |> Enum.map(&hd/1)

  defp replay do
    for args <- events(), do: apply(Dawarich.Exports.EventsWorker, :run, [ScratchRepo, args])
  end

  defp drain do
    receive do
      {:domain_changed, _, :exports} -> drain()
    after
      0 -> :ok
    end
  end

  defp blob,
    do: %{
      key: Dawarich.Storage.generate_key(),
      filename: "synthetic.zip",
      content_type: "application/zip",
      metadata: "{}",
      service_name: "local",
      byte_size: 7,
      checksum: Base.encode64(:crypto.hash(:md5, "<gpx/>"))
    }

  test "export completion and failure invalidate only their owner after commit", c do
    assert :ok = apply(Exports, :subscribe, [c.scope, c.opts])
    assert :ok = apply(Exports, :subscribe, [c.other, c.opts])
    assert {:ok, id} = request(c)
    event = Ecto.UUID.generate()
    assert {:run, record} = Exports.claim(ScratchRepo, id, c.scope.user.id, event)
    replay()
    drain()
    before = events()

    assert {:error, :abort} =
             ScratchRepo.transaction(fn ->
               assert :ok =
                        Exports.complete(ScratchRepo, record, event, blob(), %{
                          title: "private title",
                          content: "private content"
                        })

               ScratchRepo.rollback(:abort)
             end)

    assert events() == before
    refute_receive {:domain_changed, _, :exports}

    assert :ok =
             Exports.complete(ScratchRepo, record, event, blob(), %{
               title: "private title",
               content: "private content"
             })

    replay()
    assert_receive {:domain_changed, owner, :exports}
    assert owner == c.scope.user.id
    refute_receive {:domain_changed, _, :exports}
    assert {:ok, id} = request(c)
    event = Ecto.UUID.generate()
    assert {:run, record} = Exports.claim(ScratchRepo, id, c.scope.user.id, event)
    replay()
    drain()

    assert :ok =
             Exports.fail!(ScratchRepo, record, event, "synthetic failure", %{
               title: "private title",
               content: "private content"
             })

    replay()
    assert_receive {:domain_changed, ^owner, :exports}
    for args <- events(), do: assert(Enum.sort(Map.keys(args)) == ["event_id", "user_id"])
    replay()
    refute_receive {:domain_changed, _, :exports}
  end

  test "export replay keeps one artifact and late completion cannot revive a deleted export", c do
    assert {:ok, id} = request(c)
    event = Ecto.UUID.generate()
    assert {:run, record} = Exports.claim(ScratchRepo, id, c.scope.user.id, event)

    rows("UPDATE phoenix.export_claims SET event_id=$2 WHERE export_id=$1", [
      id,
      Ecto.UUID.dump!(Ecto.UUID.generate())
    ])

    assert :lost =
             Exports.complete(ScratchRepo, record, event, blob(), %{title: "T", content: "C"})

    assert rows("SELECT count(*) FROM active_storage_blobs") == [[0]]

    rows("UPDATE phoenix.export_claims SET event_id=$2 WHERE export_id=$1", [
      id,
      Ecto.UUID.dump!(event)
    ])

    assert :ok = Exports.complete(ScratchRepo, record, event, blob(), %{title: "T", content: "C"})

    assert :lost =
             Exports.complete(ScratchRepo, record, event, blob(), %{title: "T", content: "C"})

    assert rows("SELECT count(*) FROM active_storage_blobs") == [[1]]
    assert {:ok, :deleted} = apply(Exports, :delete, [c.scope, id, c.opts])

    assert :lost =
             Exports.complete(ScratchRepo, record, event, blob(), %{title: "T", content: "C"})

    assert rows("SELECT count(*) FROM exports") == [[0]]
    assert rows("SELECT count(*) FROM active_storage_attachments") == [[0]]
  end

  test "foreign inactive and revoked actors cannot create or delete through the scoped interface",
       c do
    assert {:error, :invalid_submission} =
             apply(Exports, :request, [
               c.scope,
               Map.put(params(), "file_format", "forged"),
               c.opts
             ])

    assert {:ok, id} = request(c)
    assert {:error, :not_found} = apply(Exports, :delete, [c.other, id, c.opts])
    rows("UPDATE users SET active_until=now()-interval '1 second' WHERE id=$1", [c.scope.user.id])
    assert {:error, :inactive} = request(c)
    assert {:error, :inactive} = apply(Exports, :delete, [c.scope, id, c.opts])

    rows(
      "UPDATE users SET active_until=now()+interval '1 day',encrypted_password=encrypted_password||'rotated' WHERE id=$1",
      [c.scope.user.id]
    )

    rows("UPDATE users SET encrypted_password='different identity fingerprint' WHERE id=$1", [
      c.scope.user.id
    ])

    assert {:error, :stale_session} = request(c)
    assert {:error, :stale_session} = apply(Exports, :delete, [c.scope, id, c.opts])
    assert rows("SELECT count(*) FROM exports") == [[1]]
  end

  test "scoped export reads keep owner sorting and refuse stale identities", c do
    assert {:ok, id} = request(c)
    list = %{column: "created_at", direction: :desc, page: 1}

    assert {:ok, %{entries: [%{id: ^id, status: "created", file_format: "json"}], total_pages: 1}} =
             Exports.page(c.scope, list, c.opts)

    assert {:ok, %{entries: []}} = Exports.page(c.other, list, c.opts)
    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [c.scope.user.id])
    assert {:error, :stale_session} = Exports.page(c.scope, list, c.opts)
    assert {:error, :stale_session} = Exports.subscribe(c.scope, c.opts)
  end

  test "native export requests refuse unavailable producer ownership without a handback", c do
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:exports.points", :sidekiq)
    assert {:error, :not_owned} = request(c)
    assert rows("SELECT count(*) FROM exports") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  test "export invalidation relay refuses an uncommitted intent", c do
    assert {:ok, _} = request(c)
    [intent] = events()
    assert :ok = Exports.subscribe(c.scope, c.opts)

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               assert_raise ArgumentError, fn ->
                 Dawarich.Exports.EventsWorker.run(ScratchRepo, intent)
               end

               refute_receive {:domain_changed, _, :exports}
               :ok
             end)

    assert :ok = Dawarich.Exports.EventsWorker.run(ScratchRepo, intent)
    assert_receive {:domain_changed, owner, :exports}
    assert owner == c.scope.user.id
  end
end
