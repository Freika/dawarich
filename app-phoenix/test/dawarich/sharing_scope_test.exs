defmodule Dawarich.SharingScopeTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.{Sharing, SharedLinks}
  alias Dawarich.Accounts.{Principal, Scope}
  alias Dawarich.Test.{FrameSeeds, StatsSeeds}

  @now ~U[2026-10-03 10:00:00Z]
  @old "a9f10000-0000-4000-8000-000000000001"
  @phrase "old-fixture-phrase"

  setup do
    actor = FrameSeeds.seed_management!("hub_active_shared_en")
    cable = Application.get_env(:dawarich, :cable)
    Application.put_env(:dawarich, :cable, transport: :pg, bus: false)
    on_exit(fn -> Application.put_env(:dawarich, :cable, cable) end)
    StatsSeeds.stat!(actor.id, %{year: 2025, month: 7})
    StatsSeeds.digest!(actor.id, %{year: 2025})

    Repo.query!(
      "INSERT INTO tracks (id,user_id,start_at,end_at,original_path,created_at,updated_at) VALUES (10951,$1,$2,$2,ST_GeomFromText('LINESTRING(0 0,1 1)',4326),$2,$2)",
      [actor.id, DateTime.to_naive(@now)],
      log: false
    )

    %{actor: actor, scope: Scope.for_user(Principal.project(actor), "en")}
  end

  defp resource(type, fields \\ %{}), do: Map.merge(%{type: type, owner_id: 98101}, fields)
  defp opts, do: [now: @now, self_hosted: true]

  defp snapshots do
    for table <- ~w(shared_links stats digests achievement_progresses), into: %{} do
      {table, Repo.query!("SELECT to_jsonb(t) FROM #{table} t ORDER BY id", [], log: false).rows}
    end
  end

  defp intents,
    do:
      Repo.query!(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Sharing.EventsWorker' ORDER BY id",
        [],
        log: false
      ).rows

  test "every sharing resource refuses a foreign owner and malformed action without effects",
       ctx do
    before = snapshots()

    for target <- [
          resource(:hub),
          resource(:live),
          resource(:trip, %{id: 99101}),
          resource(:track, %{id: 10951}),
          resource(:timeline),
          resource(:shared, %{id: @old}),
          resource(:month, %{year: 2025, month: 7}),
          resource(:digest, %{year: 2025}),
          resource(:achievement, %{key: "country_de"})
        ] do
      foreign = %{target | owner_id: 98102}
      assert {:error, :unauthorized} = Sharing.page(ctx.scope, foreign, %{}, opts())
      assert {:error, :unauthorized} = Sharing.change(ctx.scope, foreign, :create, %{}, opts())
      assert {:error, :invalid_input} = Sharing.change(ctx.scope, target, :send, %{}, opts())
    end

    assert {:error, :not_found} =
             Sharing.page(ctx.scope, resource(:trip, %{id: 99102}), %{}, opts())

    assert {:error, :invalid_input} =
             Sharing.page(ctx.scope, resource(:trip, %{id: "1 OR true"}), %{}, opts())

    assert {:error, :invalid_input} =
             Sharing.change(ctx.scope, resource(:live), :create, %{"shared_link" => []}, opts())

    assert snapshots() == before
    assert intents() == []
  end

  test "sharing snapshots and validation never retain phrases or actor credentials", ctx do
    for target <- [resource(:hub), resource(:live), resource(:shared, %{id: @old})] do
      assert {:ok, page} = Sharing.page(ctx.scope, target, %{}, opts())
      refute inspect(page) =~ @phrase
      refute inspect(page) =~ "api_key"
      refute inspect(page) =~ "encrypted_password"
    end

    assert {:error, %{errors: [_ | _]} = error} =
             Sharing.change(
               ctx.scope,
               resource(:live),
               :create,
               %{
                 "shared_link" => %{
                   "name" => String.duplicate("x", 256),
                   "magic_phrase" => "transient-only-phrase"
                 }
               },
               opts()
             )

    refute inspect(error) =~ "transient-only-phrase"

    assert {:ok, @phrase} =
             Sharing.reveal(ctx.scope, resource(:shared, %{id: @old}), :phrase, opts())

    assert {:error, :unauthorized} =
             Sharing.reveal(
               ctx.scope,
               %{resource(:shared, %{id: @old}) | owner_id: 98102},
               :phrase,
               opts()
             )
  end

  test "URL and phrase rotation preserve expiry semantics and invalidate old public admission",
       ctx do
    Repo.query!(
      "UPDATE shared_links SET expires_at=$2 WHERE id=$1::text::uuid",
      [@old, ~N[2026-10-25 00:00:00]],
      log: false
    )

    before = Sharing.version(@old)
    cookie = DawarichWeb.SharedLinkCookie.unlock_token(@old, @phrase)

    assert {:ok, result} =
             Sharing.change(ctx.scope, resource(:live), :regenerate_phrase, %{}, opts())

    assert result.share.id == @old
    refute Sharing.version(@old) == before

    assert {:ok, phrase} =
             Sharing.reveal(ctx.scope, resource(:shared, %{id: @old}), :phrase, opts())

    refute DawarichWeb.SharedLinkCookie.unlock_token(@old, phrase) == cookie
    refute inspect(result) =~ phrase
    assert {:ok, rotated} = Sharing.change(ctx.scope, resource(:live), :regenerate, %{}, opts())
    refute rotated.share.id == @old
    assert SharedLinks.active(@old, @now) == nil
    assert NaiveDateTime.compare(rotated.share.expires_at, ~N[2026-10-25 00:00:00]) == :eq
    assert Sharing.version(@old) == nil
    assert Enum.any?(intents(), fn [args] -> @old in args["public_ids"] end)
  end

  test "failed active replacement preserves recorded rollback and event effects", ctx do
    fixture =
      File.read!("test/fixtures/share_management/failed_live_replacement.json") |> Jason.decode!()

    before = snapshots()

    assert {:error, %{errors: [_ | _]}} =
             Sharing.change(ctx.scope, resource(:live), :create, fixture["params"], opts())

    assert snapshots() == before
    assert Repo.query!("SELECT count(*) FROM phoenix.cable_events", [], log: false).rows == [[2]]
    assert intents() == []
  end

  test "sharing consent uses current family audience and original actor session", ctx do
    scope = ctx.scope

    Repo.query!(
      "UPDATE users SET encrypted_password='changed-session' WHERE id=$1",
      [ctx.actor.id],
      log: false
    )

    assert {:error, :stale_session} = Sharing.page(scope, resource(:live), %{}, opts())
    assert {:error, :stale_session} = Sharing.change(scope, resource(:live), :revoke, %{}, opts())

    Repo.query!(
      "UPDATE users SET encrypted_password=$2 WHERE id=$1",
      [ctx.actor.id, ctx.actor.encrypted_password],
      log: false
    )

    assert {:error, %{errors: [_ | _]}} =
             Sharing.change(
               scope,
               resource(:trip, %{id: 99101}),
               :create,
               %{"shared_link" => %{"audience" => "family"}},
               opts()
             )

    assert intents() == []
  end

  test "report and achievement sharing preserve settings and scoped durable invalidation", ctx do
    for target <- [resource(:month, %{year: 2025, month: 7}), resource(:digest, %{year: 2025})] do
      assert {:ok, result} =
               Sharing.change(
                 ctx.scope,
                 target,
                 :update,
                 %{"enabled" => "1", "expiration" => "12h"},
                 opts()
               )

      assert result.settings["expiration"] == "12h"
      assert result.settings["enabled"]
      assert {:ok, page} = Sharing.page(ctx.scope, target, %{}, opts())
      assert page.uuid == result.uuid

      assert {:ok, disabled} =
               Sharing.change(ctx.scope, target, :update, %{"enabled" => "0"}, opts())

      refute disabled.settings["enabled"]
    end

    target = resource(:achievement, %{key: "country_de"})

    assert {:ok, %{enabled: true, uuid: uuid}} =
             Sharing.change(ctx.scope, target, :update, %{"enabled" => true}, opts())

    assert {:ok, %{enabled: false, uuid: ^uuid}} =
             Sharing.change(ctx.scope, target, :update, %{"enabled" => false}, opts())

    assert length(intents()) == 6

    for [args] <- intents() do
      assert Enum.sort(Map.keys(args)) == ~w(event_id public_ids user_id)
      assert args["user_id"] == ctx.actor.id
    end

    before = snapshots()

    assert {:error, :invalid_input} =
             Sharing.change(ctx.scope, target, :update, %{"enabled" => %{}}, opts())

    assert snapshots() == before
  end

  test "report sharing rechecks current active access and Cloud month entitlement", ctx do
    target = resource(:month, %{year: 2025, month: 7})
    cloud = [now: @now, self_hosted: false]
    Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [ctx.actor.id], log: false)
    assert {:error, :expired} = Sharing.page(ctx.scope, target, %{}, cloud)

    assert {:error, :expired} =
             Sharing.change(ctx.scope, target, :update, %{"enabled" => "1"}, cloud)

    assert {:ok, _} = Sharing.page(ctx.scope, resource(:digest, %{year: 2025}), %{}, cloud)

    Repo.query!(
      "UPDATE users SET active_until=$2 WHERE id=$1",
      [ctx.actor.id, DateTime.to_naive(@now)], log: false)

    for target <- [target, resource(:digest, %{year: 2025})] do
      assert {:error, :expired} = Sharing.page(ctx.scope, target, %{}, opts())

      assert {:error, :expired} =
               Sharing.change(ctx.scope, target, :update, %{"enabled" => "1"}, opts())
    end

    assert intents() == []
  end

  test "native sharing invalidation is ID-only idempotent and absent after rollback", ctx do
    Phoenix.PubSub.subscribe(Dawarich.PubSub, "sharing:user:#{ctx.actor.id}")
    Phoenix.PubSub.subscribe(Dawarich.PubSub, "sharing:public:#{@old}")
    assert {:ok, _} = Sharing.change(ctx.scope, resource(:live), :revoke, %{}, opts())
    [[args]] = intents()
    assert :ok = Dawarich.Sharing.EventsWorker.run(Repo, args)
    assert_receive {:domain_changed, 98101, :sharing}
    assert_receive {:share_changed, @old, version}
    assert version == Sharing.version(@old)
    assert :ok = Dawarich.Sharing.EventsWorker.run(Repo, args)
    refute_receive {:domain_changed, _, _}
    count = length(intents())

    Repo.transaction(fn ->
      assert {:ok, _} = Sharing.change(ctx.scope, resource(:live), :create, %{}, opts())
      Repo.rollback(:outer)
    end)

    assert length(intents()) == count
  end
end
