defmodule Dawarich.NotificationEventsTest do
  use ExUnit.Case, async: false
  alias Dawarich.{Repo, Notifications, Accounts.Scope, Accounts.Principal}

  setup do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      [[id]] =
        Repo.query!("SELECT nextval(pg_get_serial_sequence('users','id'))", [], log: false).rows

      user =
        Dawarich.Test.RailsUser.insert!(%{
          id: id,
          email: "native-notice-relay-#{Ecto.UUID.generate()}@example.invalid"
        })

      on_exit(fn ->
        Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
          events =
            Repo.query!(
              "SELECT args->>'event_id' FROM oban.oban_jobs WHERE worker='Dawarich.Notifications.EventsWorker' AND (args->>'user_id'=$1 OR args->>'notification_id'=$1)",
              [to_string(user.id)],
              log: false
            ).rows
            |> Enum.map(&hd/1)

          Repo.query!(
            "DELETE FROM phoenix.processed_commands WHERE event_id=ANY($1)",
            [Enum.map(events, &Ecto.UUID.dump!/1)],
            log: false
          )

          Repo.query!(
            "DELETE FROM oban.oban_jobs WHERE worker='Dawarich.Notifications.EventsWorker' AND (args->>'user_id'=$1 OR args->>'notification_id'=$1)",
            [to_string(user.id)],
            log: false
          )

          Repo.query!(
            "DELETE FROM phoenix.notification_events WHERE notification_id IN (SELECT id FROM notifications WHERE user_id=$1)",
            [user.id],
            log: false
          )

          Repo.query!(
            "DELETE FROM oban.oban_jobs WHERE worker='Dawarich.AfterCommit.Worker' AND (args->'payload'->>'user_id'=$1 OR args->'payload'->'keys' @> $2::jsonb)",
            [to_string(user.id), ["dawarich/user_#{user.id}_countries_visited"]],
            log: false
          )

          keys =
            for prefix <- ["", "phoenix/"],
                suffix <- ~w(countries_visited cities_visited total_distance years_tracked),
                do:
                  "cache:key:" <>
                    Base.encode16(
                      :crypto.hash(:sha256, "#{prefix}dawarich/user_#{user.id}_#{suffix}"),
                      case: :lower
                    )

          Repo.query!(
            "DELETE FROM phoenix.epochs WHERE key=ANY($1)",
            [["cache:user:#{user.id}" | keys]],
            log: false
          )

          Repo.query!("DELETE FROM notifications WHERE user_id=$1", [user.id], log: false)
          Repo.query!("DELETE FROM users WHERE id=$1", [user.id], log: false)
        end)
      end)

      %{user: user, scope: Scope.for_user(Principal.project(user), "en")}
    end)
  end

  defp intents(owner),
    do:
      Repo.query!(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Notifications.EventsWorker' AND (args->>'user_id'=$1 OR args->>'notification_id'=$1) ORDER BY id",
        [to_string(owner)],
        log: false
      ).rows
      |> Enum.map(&hd/1)

  defp subscribe(owner), do: apply(Dawarich.Notifications.Events, :subscribe, [owner])
  defp relay(args), do: apply(Dawarich.Notifications.EventsWorker, :run, [Repo, args])

  defp notice(owner) do
    id =
      Notifications.create!(
        Repo,
        owner,
        :info,
        "private synthetic title",
        "private synthetic body"
      )

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("DELETE FROM phoenix.notification_events WHERE notification_id=$1", [id],
          log: false
        )
      end)
    end)

    id
  end

  test "delete-all invalidation survives relay restart without its deleted rows", c do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      :ok = subscribe(c.user.id)
      id = notice(c.user.id)
      [creation] = intents(c.user.id)
      assert :ok = relay(creation)
      assert_receive {:domain_changed, owner, :notifications}
      assert owner == c.user.id
      assert {:ok, {1, nil}} = Notifications.delete_all(c.scope)
      [^creation, deletion] = intents(c.user.id)
      assert Map.keys(deletion) |> Enum.sort() == ["event_id", "user_id"]
      assert deletion["user_id"] == c.user.id
      assert Repo.query!("SELECT id FROM notifications WHERE id=$1", [id], log: false).rows == []

      task =
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn -> relay(deletion) end)
        end)

      assert Task.await(task) == :ok
      assert_receive {:domain_changed, ^owner, :notifications}
      assert :ok = relay(deletion)
      refute_receive {:domain_changed, ^owner, :notifications}, 30
      assert {:ok, %{notifications: []}} = Notifications.page(c.scope, 1)
    end)
  end

  test "rollback emits no native event and duplicate replay converges", c do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      :ok = subscribe(c.user.id)

      assert {:error, :rollback} =
               Repo.transaction(fn ->
                 notice(c.user.id)
                 Repo.rollback(:rollback)
               end)

      assert intents(c.user.id) == []
      refute_receive {:domain_changed, _, :notifications}, 30
      id = notice(c.user.id)
      [intent] = intents(c.user.id)
      assert_raise ArgumentError, fn -> Repo.transaction(fn -> relay(intent) end) end
      assert :ok = relay(intent)
      assert_receive {:domain_changed, owner, :notifications}
      assert owner == c.user.id
      assert :ok = relay(intent)
      refute_receive {:domain_changed, _, :notifications}, 30
      assert {:ok, %{count: 1, items: [%{id: ^id}]}} = Notifications.unread(c.scope)
      assert {:ok, _} = Notifications.open(c.scope, id)
      [^intent, read_intent] = intents(c.user.id)
      assert :ok = relay(read_intent)
      assert_receive {:domain_changed, ^owner, :notifications}
      assert {:ok, %{count: 0}} = Notifications.unread(c.scope)
    end)
  end

  test "notification create update mark-all and single delete persist only owner identities", c do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      id = notice(c.user.id)

      assert :ok =
               Notifications.update_with_broadcast!(Repo, c.user.id, id, %{
                 "content" => "changed private body"
               })

      assert {:ok, {1, nil}} = Notifications.mark_all_read(c.scope)
      assert {:ok, :deleted} = Notifications.delete(c.scope, id)
      assert length(intents(c.user.id)) == 4

      assert Enum.all?(intents(c.user.id), fn args ->
               Enum.sort(Map.keys(args)) == ["event_id", "user_id"] and
                 args["user_id"] == c.user.id
             end)
    end)
  end

  test "restored notification batches commit one owner invalidation and rollback together", c do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      context = %{now: NaiveDateTime.utc_now()}

      notes = [
        %{"title" => "restored synthetic", "content" => "restored private body", "kind" => "info"}
      ]

      assert Dawarich.UserData.Restore.Notifications.call(Repo, c.user.id, notes, context) == 1
      assert [intent] = intents(c.user.id)
      assert Dawarich.UserData.Restore.Notifications.call(Repo, c.user.id, notes, context) == 0
      assert intents(c.user.id) == [intent]

      assert {:error, :rollback} =
               Repo.transaction(fn ->
                 fresh = [
                   %{
                     "title" => "rolled back synthetic",
                     "content" => "rolled back private",
                     "kind" => "info"
                   }
                 ]

                 assert Dawarich.UserData.Restore.Notifications.call(
                          Repo,
                          c.user.id,
                          fresh,
                          context
                        ) == 1

                 Repo.rollback(:rollback)
               end)

      assert intents(c.user.id) == [intent]

      assert Repo.query!("SELECT count(*) FROM notifications WHERE user_id=$1", [c.user.id],
               log: false
             ).rows == [[1]]
    end)
  end

  test "account removal persists an owner wake without its deleted notification rows", c do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      notice(c.user.id)

      assert {:ok, :ok} =
               Repo.transaction(fn ->
                 Repo.query!("UPDATE users SET deleted_at=now() WHERE id=$1", [c.user.id],
                   log: false
                 )

                 Dawarich.Users.DestroyEffects.call(Repo, c.user.id, Ecto.UUID.generate())
               end)

      assert Repo.query!("SELECT id FROM users WHERE id=$1", [c.user.id], log: false).rows == []
      assert [creation, deletion] = intents(c.user.id)
      assert creation["user_id"] == deletion["user_id"]
      assert Enum.sort(Map.keys(deletion)) == ["event_id", "user_id"]
      assert {:error, :stale_session} = Notifications.page(c.scope, 1)
    end)
  end
end
