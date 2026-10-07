defmodule AfterCommitReviewRepo do
  def query!(sql, params \\ [], opts \\ []) do
    if Process.get(:review_fail_followup) && String.starts_with?(sql, "INSERT INTO job_outbox"),
      do: raise("review follow-up insert failed")

    Dawarich.ScratchRepo.query!(sql, params, opts)
  end

  def in_transaction?(), do: Dawarich.ScratchRepo.in_transaction?()
  def one(query, opts), do: Dawarich.ScratchRepo.one(query, opts)
  def update!(changeset, opts), do: Dawarich.ScratchRepo.update!(changeset, opts)

  def insert!(changeset, opts) do
    if Process.get(:review_fail_enqueue), do: raise("review enqueue failed")
    Dawarich.ScratchRepo.insert!(changeset, opts)
  end

  def transaction(fun), do: Dawarich.ScratchRepo.transaction(fun)
  def rollback(reason), do: Dawarich.ScratchRepo.rollback(reason)
end

defmodule AfterCommitReviewRedisPublisher do
  use GenServer

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Dawarich.Cable.Bus.Publisher)

  def init(opts), do: {:ok, %{n: 0, conn: opts[:conn]}}

  def handle_cast({:pipeline, [command], from}, state) do
    n = state.n + 1
    result = Redix.command(state.conn, command)

    reply =
      if n == 2 do
        {:error, %Redix.ConnectionError{reason: :closed}}
      else
        case result do
          {:ok, value} -> {:ok, [value]}
          error -> error
        end
      end

    send(from, {from, reply})
    {:noreply, %{state | n: n}}
  end
end

defmodule AfterCommitReviewTileSource do
  def fetch(user, _) do
    [[n]] =
      Dawarich.Repo.query!("SELECT count(*) FROM tracks WHERE user_id=$1", [user.id], log: false).rows

    {:ok, "synthetic-tile-count-#{n}", nil}
  end
end

defmodule Dawarich.AfterCommitReviewTest do
  use Dawarich.JobsCase, async: false
  import Dawarich.AnomalyCase
  alias Dawarich.AfterCommit
  @at 1_767_225_600

  setup do
    old = Application.get_env(:dawarich, :cable)
    on_exit(fn -> Application.put_env(:dawarich, :cable, old) end)
    Enum.each(Dawarich.Redis.cache_child_specs(), &start_supervised!/1)
    :ok
  end

  test "P1 family follow-up must roll back with subscription or remain replayable" do
    user = user!()
    rows("UPDATE users SET plan=0,status=0,api_key='synthetic-review-key' WHERE id=$1", [user])

    claims = %{
      "user_id" => user,
      "event_id" => Ecto.UUID.generate(),
      "exp" => System.os_time(:second) + 300,
      "plan" => "family",
      "status" => "active",
      "subscription_source" => "paddle"
    }

    ctx = %{
      repo: AfterCommitReviewRepo,
      env: %{
        "SUBSCRIPTION_WEBHOOK_SECRET" => "synthetic-review-webhook",
        "JWT_SECRET_KEY" => "synthetic-review-jwt"
      },
      native: true,
      self_hosted: false
    }

    header = Base.url_encode64(Jason.encode!(%{"alg" => "HS256"}), padding: false)
    payload = Base.url_encode64(Jason.encode!(claims), padding: false)

    signature =
      :crypto.mac(:hmac, :sha256, ctx.env["JWT_SECRET_KEY"], header <> "." <> payload)
      |> Base.url_encode64(padding: false)

    token = Enum.join([header, payload, signature], ".")
    Process.put(:review_fail_followup, true)

    assert_raise RuntimeError, "review follow-up insert failed", fn ->
      Dawarich.Subscriptions.Callback.call(token, "synthetic-review-webhook", ctx)
    end

    Process.delete(:review_fail_followup)
    assert rows("SELECT plan FROM users WHERE id=$1", [user]) == [[0]]
    replay = Dawarich.Subscriptions.Callback.call(token, "synthetic-review-webhook", ctx)

    observation = %{
      plan: rows("SELECT plan FROM users WHERE id=$1", [user]),
      jobs: rows("SELECT command_type FROM job_outbox"),
      replay: replay
    }

    assert observation.plan == [[2]]
    assert observation.jobs == [["families.auto_create"]]
    assert elem(observation.replay, 2) =~ "subscription_updated"
  end

  test "P3 a legacy completed live broadcast must remain suppressed" do
    user = user!()
    Application.put_env(:dawarich, :cable, transport: :pg, repo: ScratchRepo)
    id = Ecto.UUID.generate()
    assert Dawarich.State.claim(ScratchRepo, "live_broadcast:done:#{id}", 86_400)

    args = %{
      "user_id" => user,
      "broadcast_id" => id,
      "payloads" => [],
      "upserted" => [%{"id" => 1, "timestamp" => @at, "longitude" => 13.4, "latitude" => 52.5}]
    }

    assert :ok = Dawarich.Points.LiveBroadcastWorker.run(ScratchRepo, args)
    events = rows("SELECT count(*) FROM phoenix.cable_events")
    assert events == [[0]]
    assert Dawarich.Jobs.Processed.done?(ScratchRepo, id)
  end

  test "P4 native Redis track batch must not duplicate its first event on retry" do
    user = user!()
    Application.put_env(:dawarich, :cable, transport: :redis)
    url = Application.fetch_env!(:dawarich, :redis)[:url]
    conn = start_supervised!({Redix, {url, []}})
    pubsub = start_supervised!(%{id: Redix.PubSub, start: {Redix.PubSub, :start_link, [url, []]}})

    channel =
      Dawarich.Cable.Bus.channel(Dawarich.RailsMessages.broadcasting(["tracks", {:user, user}]))

    {:ok, ref} = Redix.PubSub.subscribe(pubsub, channel, self())
    assert_receive {:redix_pubsub, ^pubsub, ^ref, :subscribed, _}
    start_supervised!({AfterCommitReviewRedisPublisher, conn: conn})

    payload = %{
      "user_id" => user,
      "created" => [],
      "updated" => [],
      "destroyed" => [1, 2],
      "min_ts" => @at,
      "max_ts" => @at
    }

    AfterCommit.cache(ScratchRepo, "tracks", payload)
    [[args]] = rows("SELECT args FROM oban.oban_jobs")
    assert {:error, _} = AfterCommit.Worker.run(ScratchRepo, args)
    assert :ok = AfterCommit.Worker.run(ScratchRepo, args)
    assert_receive {:redix_pubsub, ^pubsub, ^ref, :message, %{payload: first}}
    assert_receive {:redix_pubsub, ^pubsub, ^ref, :message, %{payload: second}}
    assert Jason.decode!(first)["track_id"] == 1
    assert Jason.decode!(second)["track_id"] == 2
    refute_receive {:redix_pubsub, ^pubsub, ^ref, :message, _}
  end

  test "P5 committed create intent must retain the original created effect" do
    user = user!()
    Application.put_env(:dawarich, :cable, transport: :pg, repo: ScratchRepo)
    id = track!(user)

    payload = %{
      "user_id" => user,
      "created" => [id],
      "updated" => [],
      "destroyed" => [],
      "min_ts" => @at,
      "max_ts" => @at + 60
    }

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               Dawarich.Tracks.NativeChanges.write!(ScratchRepo, payload)
             end)

    rows("DELETE FROM tracks WHERE id=$1", [id])
    [[args]] = rows("SELECT args FROM oban.oban_jobs")
    assert :ok = AfterCommit.Worker.run(ScratchRepo, args)
    count = rows("SELECT count(*) FROM phoenix.cable_events")
    assert count == [[1]]
    [[message]] = rows("SELECT payload FROM phoenix.cable_events")

    assert %{"action" => "created", "track" => %{"id" => ^id, "distance" => 100}} =
             Jason.decode!(message)
  end

  test "P6 discarded track intent cannot validate the predelete tile" do
    repo = Dawarich.Repo

    Ecto.Adapters.SQL.Sandbox.unboxed_run(repo, fn ->
      [[user]] =
        repo.query!(
          "INSERT INTO users(email,settings,created_at,updated_at) VALUES($1,'{}',now(),now()) RETURNING id",
          ["tile-review-#{Ecto.UUID.generate()}@example.test"],
          log: false
        ).rows

      try do
        [[id]] =
          repo.query!(
            "INSERT INTO tracks(user_id,start_at,end_at,original_path,created_at,updated_at) VALUES($1,'2026-01-01','2026-01-01 00:01:00',ST_GeomFromText('LINESTRING(13 52,14 53)',4326),now(),now()) RETURNING id",
            [user],
            log: false
          ).rows

        actor = %{id: user, timezone: "UTC", plan: 2, status: 1, active_until: nil}

        base =
          Plug.Test.conn(:get, "/synthetic.mvt")
          |> Plug.Conn.assign(:api_user, actor)
          |> Plug.Conn.assign(:api_params, %{
            "start_at" => to_string(@at),
            "end_at" => to_string(@at + 60),
            "z" => "0",
            "x" => "0",
            "y" => "0"
          })

        first = Dawarich.Tiles.Http.call(base, "tracks", AfterCommitReviewTileSource, "review")
        assert first.status == 200
        [etag] = Plug.Conn.get_resp_header(first, "etag")

        assert {:ok, :ok} =
                 repo.transaction(fn ->
                   repo.query!("DELETE FROM tracks WHERE id=$1", [id], log: false)

                   Dawarich.Tracks.NativeChanges.write!(repo, %{
                     "user_id" => user,
                     "created" => [],
                     "updated" => [],
                     "destroyed" => [id],
                     "min_ts" => @at,
                     "max_ts" => @at + 60
                   })
                 end)

        repo.query!(
          "UPDATE oban.oban_jobs SET state='discarded',attempt=max_attempts,inserted_at=now()-interval '1 day',discarded_at=now() WHERE args->'payload'->>'user_id'=$1",
          [to_string(user)],
          log: false
        )

        second =
          base
          |> Plug.Conn.put_req_header("if-none-match", etag)
          |> Dawarich.Tiles.Http.call("tracks", AfterCommitReviewTileSource, "review")

        assert repo.query!("SELECT count(*) FROM tracks WHERE user_id=$1", [user], log: false).rows ==
                 [[0]]

        assert second.status != 304
        refute Plug.Conn.get_resp_header(second, "etag") == [etag]
      after
        repo.query!(
          "DELETE FROM oban.oban_jobs WHERE args->'payload'->>'user_id'=$1",
          [to_string(user)],
          log: false
        )

        repo.query!("DELETE FROM phoenix.epochs WHERE key LIKE $1", ["%:#{user}"], log: false)
        repo.query!("DELETE FROM users WHERE id=$1", [user], log: false)
      end
    end)
  end

  test "P7 restored-import anomaly flags must commit with all downstream intents" do
    old_mode = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if old_mode,
        do: System.put_env("DAWARICH_RAILS", old_mode),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    user = user!()
    point = point!(user, @at, {13.4, 52.5}, accuracy: 20_000)

    ctx = %{
      zone: "UTC",
      report: fn _, _ -> :ok end,
      fence: fn effect ->
        {:ok, result} = ScratchRepo.transaction(effect)
        result
      end
    }

    Process.put(:review_fail_enqueue, true)
    assert Dawarich.UserData.Restore.filter(AfterCommitReviewRepo, user, ctx) == 0
    Process.delete(:review_fail_enqueue)
    assert flagged(user) == []
    assert Dawarich.UserData.Restore.filter(AfterCommitReviewRepo, user, ctx) == 1

    observation = %{
      flagged: rows("SELECT anomaly FROM points WHERE id=$1", [point]),
      jobs: rows("SELECT worker FROM oban.oban_jobs")
    }

    assert observation.flagged == [[true]]
    assert length(observation.jobs) == 2
  end

  test "P6 subscription plan readers reject old caches before eviction runs" do
    repo = Dawarich.Repo
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(repo)

    user =
      Dawarich.Test.RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "cache-bound@example.test",
        api_key: Ecto.UUID.generate(),
        plan: 0
      })

    assert DawarichWeb.RateLimit.plan(user.api_key) == "lite"
    repo.query!("UPDATE users SET plan=2 WHERE id=$1", [user.id], log: false)
    AfterCommit.cache(repo, "subscription", %{"user_id" => user.id})
    assert DawarichWeb.RateLimit.plan(user.api_key) == "family"
  end

  test "P6 precommit warming cannot store its old value in the committed generation" do
    repo = Dawarich.Repo
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(repo)
    id = System.unique_integer([:positive])
    key = "phoenix/dawarich/user_#{id}_countries_visited"
    signature = :crypto.hash(:sha256, :erlang.term_to_binary([%{distance: 999, toponyms: []}]))

    hook = fn suffix ->
      if suffix == "countries_visited", do: AfterCommit.cache(repo, "stats", %{"user_id" => id})
    end

    Dawarich.Cache.Readers.summary(id, [%{distance: 999, toponyms: []}],
      repo: repo,
      before_warm_write: hook
    )

    next = Dawarich.AfterCommit.Visibility.key(repo, key)
    assert next != key

    refute Dawarich.Redis.cache_command(["GET", next]) ==
             {:ok, "DW1" <> :erlang.term_to_binary(%{signature: signature, value: []})}
  end

  defp track!(user) do
    [[id]] =
      rows(
        "INSERT INTO tracks(user_id,start_at,end_at,original_path,distance,duration,avg_speed,created_at,updated_at) VALUES($1,'2026-01-01','2026-01-01 00:01:00',ST_GeomFromText('LINESTRING(13.4 52.5,13.5 52.6)',4326),100,60,6,now(),now()) RETURNING id",
        [user]
      )

    id
  end
end
