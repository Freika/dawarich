defmodule Dawarich.FamiliesSnapshotRaceTest do
  use ExUnit.Case, async: true

  alias Dawarich.{Accounts, Families, Repo}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.FrameSeeds

  @now ~U[2026-10-03 10:00:00Z]

  setup do
    Code.ensure_loaded!(Dawarich.Accounts.User)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    owner = FrameSeeds.seed_family!(FrameSeeds.load_family("consented_map_en"))

    settings = %{
      "family" => %{
        "location_sharing" => %{
          "enabled" => true,
          "share_history" => true,
          "history_before_sharing" => true,
          "history_window" => "all",
          "expires_at" => DateTime.to_iso8601(DateTime.add(@now, 1))
        }
      }
    }

    Repo.query!("UPDATE users SET settings=$1 WHERE id=90102", [settings], log: false)

    [[invitation_id] | _] =
      Repo.query!(
        "SELECT id FROM family_invitations WHERE family_id=91001 AND status=0 AND expires_at>$1 ORDER BY id",
        [DateTime.to_naive(@now)],
        log: false
      ).rows

    Repo.query!(
      "INSERT INTO trips(id,user_id,name,started_at,ended_at,created_at,updated_at) VALUES(998881,90102,'Synthetic family trip','2026-10-01','2026-10-03',now(),now())",
      [],
      log: false
    )

    Repo.query!(
      "INSERT INTO shared_links(id,user_id,resource_type,resource_id,name,settings,created_at,updated_at) VALUES($1::text::uuid,90102,0,998881,'Synthetic family share',$2,now(),now())",
      [Ecto.UUID.generate(), %{"audience" => "family", "family_id" => "91001"}],
      log: false
    )

    %{
      scope: Scope.for_user(Accounts.Principal.project(owner), "en"),
      invitation_id: invitation_id
    }
  end

  test "guarded family refusal leaves the surrounding ingestion transaction usable", c do
    Repo.transaction(fn ->
      assert_raise ArgumentError, "synthetic unsupported family input", fn ->
        Families.Snapshot.read(c.scope.user, [now: @now], fn ->
          raise ArgumentError, "synthetic unsupported family input"
        end)
      end

      assert Repo.query!("SELECT 1", [], log: false).rows == [[1]]
    end)
  end

  test "OwnTracks friends preserve API admission for a password-locked actor and recheck its identity",
       c do
    Repo.query!("UPDATE users SET locked_at=now() WHERE id=$1", [c.scope.user.id], log: false)
    assert [_ | _] = Dawarich.Ingest.Friends.for_user(c.scope.user.id, @now)

    assert Dawarich.Ingest.Friends.for_user(c.scope.user.id, @now,
             clock: fn -> @now end,
             after_read: fn result ->
               assert {:ok, [_ | _]} = result

               Repo.query!(
                 "UPDATE users SET encrypted_password=$2 WHERE id=$1",
                 [c.scope.user.id, "synthetic-revoked-api-identity"], log: false)

               result
             end
           ) == []
  end

  for kind <- [:locations, :history], change <- [:consent, :member, :viewer, :expiry, :access] do
    @kind kind
    @change change
    test "#{kind} discards coordinates when #{change} changes during the point read", c do
      parent = self()

      pause = fn result ->
        send(parent, {:point_read, self()})

        receive do
          {:resume, now, revoke} ->
            revoke.()
            Process.put(:family_read_now, now)
        after
          5000 -> raise "snapshot barrier timed out"
        end

        result
      end

      task =
        Task.async(fn ->
          receive do
            :start -> :ok
          end

          opts = [
            location_reader: fn user, now ->
              pause.(Dawarich.Families.Locations.read(user, now))
            end,
            history_reader: fn user, params, now ->
              pause.(Dawarich.Families.History.read(user, params, now))
            end,
            self_hosted: @change != :access,
            clock: fn -> Process.get(:family_read_now, @now) end,
            now: @now
          ]

          case @kind do
            :locations ->
              Families.locations(c.scope, opts)

            :history ->
              Families.history(
                c.scope,
                %{"start_at" => "2026-10-01T00:00:00Z", "end_at" => "2026-10-03T10:00:00Z"},
                opts
              )
          end
        end)

      :ok = Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, task.pid)
      send(task.pid, :start)
      assert_receive {:point_read, reader}, 5000

      revoke = fn ->
        case @change do
          :consent ->
            Repo.query!("UPDATE users SET settings='{}' WHERE id=90102", [], log: false)

          :member ->
            Repo.query!("DELETE FROM family_memberships WHERE user_id=90102", [], log: false)

          :viewer ->
            Repo.query!("DELETE FROM family_memberships WHERE user_id=90101", [], log: false)

          :access ->
            Repo.query!("UPDATE users SET plan=1 WHERE id=90101", [], log: false)

            Repo.query!(
              "UPDATE families SET access_until=$1 WHERE id=91001",
              [DateTime.to_naive(@now)],
              log: false
            )

          :expiry ->
            :ok
        end
      end

      send(
        reader,
        {:resume, if(@change == :expiry, do: DateTime.add(@now, 1), else: @now), revoke}
      )

      assert {:error, _} = Task.await(task, 5000)
    end
  end

  for reader <- [
        :page,
        :edit,
        :invitations,
        :request,
        :reveal,
        :raw_page,
        :raw_locations,
        :raw_history,
        :mine,
        :closure,
        :closure_locations,
        :closure_history,
        :closure_lapsed,
        :friends,
        :trips
      ],
      change <- [:consent, :viewer, :expiry, :access, :identity] do
    @reader reader
    @change change
    test "#{reader} rejects private publication after in-flight #{change} revocation", c do
      parent = self()

      if @reader == :closure_lapsed do
        Repo.query!("UPDATE users SET plan=1 WHERE id=90101", [], log: false)
        Repo.query!("UPDATE families SET access_until=NULL WHERE id=91001", [], log: false)
      end

      scope = if @reader == :request, do: Scope.for_user(Accounts.get(90102), "en"), else: c.scope

      task =
        Task.async(fn ->
          receive do
            :start -> :ok
          end

          opts = [
            now: @now,
            self_hosted: @change != :access,
            clock: fn -> Process.get(:family_publication_now, @now) end,
            after_read: fn result ->
              assert match?({:ok, _}, result) or match?({:ok, 200, _}, result)
              if @reader == :friends, do: assert(match?({:ok, [_, _ | _]}, result))
              if @reader == :trips, do: assert(match?({:ok, %{entries: [_ | _]}}, result))
              send(parent, {:private_read, self()})

              receive do
                {:publish, now, revoke} ->
                  revoke.()
                  Process.put(:family_publication_now, now)
              after
                5000 -> raise "private publication barrier timed out"
              end

              result
            end
          ]

          params = %{"start_at" => "2026-10-01T00:00:00Z", "end_at" => "2026-10-03T10:00:00Z"}
          user = Accounts.get(scope.user.id) |> Map.put(:timezone, "UTC")

          case @reader do
            :friends ->
              apply(Dawarich.Ingest.Friends, :for_user, [user.id, @now, opts])

            :trips ->
              apply(Dawarich.SharedLinks.FamilyAudience, :trips, [user, 1, @now, opts])

            :page ->
              Families.page(scope, :show, opts)

            :edit ->
              Families.page(scope, :edit, opts)

            :invitations ->
              Families.page(scope, :invitations, opts)

            :request ->
              Families.page(scope, {:request, 94001}, opts)

            :reveal ->
              Families.reveal_invitation(scope, c.invitation_id, opts)

            :raw_page ->
              Dawarich.FamilyPage.read(user, :show, opts)

            :raw_locations ->
              Dawarich.Families.Locations.read(user, @now, opts)

            :raw_history ->
              Dawarich.Families.History.read(user, params, @now, opts)

            :mine ->
              Dawarich.Families.Mine.read(user, @now, opts)

            :closure ->
              Dawarich.FamilyApi.Closure.run(:mine, user, %{}, @now, opts)

            :closure_lapsed ->
              Dawarich.FamilyApi.Closure.run(:mine, user, %{}, @now, opts)

            :closure_locations ->
              Dawarich.FamilyApi.Closure.run(:locations, user, %{}, @now, opts)

            :closure_history ->
              Dawarich.FamilyApi.Closure.run(:history, user, params, @now, opts)
          end
        end)

      :ok = Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, task.pid)
      send(task.pid, :start)
      assert_receive {:private_read, pid}, 5000

      revoke = fn ->
        case @change do
          :consent ->
            Repo.query!("UPDATE users SET settings='{}' WHERE id=90102", [], log: false)

          :identity ->
            Repo.query!(
              "UPDATE users SET encrypted_password='changed-identity' WHERE id=$1",
              [scope.user.id],
              log: false
            )

          :viewer ->
            Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [scope.user.id],
              log: false
            )

          :access ->
            Repo.query!("UPDATE users SET plan=1 WHERE id=90101", [], log: false)

            Repo.query!(
              "UPDATE families SET access_until=$1 WHERE id=91001",
              [DateTime.to_naive(@now)],
              log: false
            )

          :expiry ->
            :ok
        end
      end

      send(pid, {:publish, if(@change == :expiry, do: DateTime.add(@now, 1), else: @now), revoke})
      result = Task.await(task, 5000)

      assert match?({:error, _}, result) or match?({:ok, 403, _}, result) or
               (@reader == :friends and result == []) or
               (@reader == :trips and result == %{entries: [], total_pages: 0}),
             "#{@reader} published a stale private document"
    end
  end

  test "a locations snapshot carries the consent boundary its validated read admitted", c do
    {:ok, clock} = Agent.start_link(fn -> [@now, @now, @now, DateTime.add(@now, 1)] end)

    read = fn ->
      Agent.get_and_update(clock, fn
        [at] -> {at, [at]}
        [at | rest] -> {at, rest}
      end)
    end

    assert {:ok, snapshot} = Families.locations(c.scope, clock: read, self_hosted: true)
    assert [%{"user_id" => 90102}] = snapshot.locations
    assert snapshot.deadline == DateTime.to_naive(DateTime.add(@now, 1))
    assert {:ok, later} = Families.deadline(c.scope, clock: read, self_hosted: true)
    assert NaiveDateTime.compare(later, snapshot.deadline) == :gt
  end
end
