defmodule Dawarich.ShareManagement.MutationsTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.ShareManagement.Mutations
  alias Dawarich.Test.FrameSeeds

  @now ~U[2026-10-03 10:00:00Z]

  setup do
    actor = FrameSeeds.seed_management!("hub_active_shared_en")
    %{actor: actor}
  end

  @tag mutation: :rollback
  test "invalid active live replacement replays before native writes and retains Rails rollback plus revoked event",
       ctx do
    fixture =
      "test/fixtures/share_management/failed_live_replacement.json"
      |> File.read!()
      |> Jason.decode!()

    assert fixture["status"] == 422
    assert fixture["before"] == fixture["after"]
    assert [%{"message" => %{"revoked" => true}, "stream" => stream}] = fixture["events"]

    assert stream ==
             "shared_location:" <>
               Base.encode64("gid://dawarich/SharedLink/" <> id(1), padding: false)

    before = rows()
    params = fixture["params"]
    assert Mutations.run(ctx.actor, "live", nil, :create, params, "en", now: @now) == :rails
    assert rows() == before
    assert commands() == []
  end

  @tag mutation: :old_url
  test "URL rotation creates new row and retires old UUID preserving future expiry", ctx do
    Repo.query!(
      "UPDATE shared_links SET expires_at = $1, view_count = 12 WHERE id = $2::text::uuid",
      [~N[2026-10-25 00:00:00], id(1)]
    )

    assert {:ok, %{share: share, committed?: true}} =
             Mutations.run(ctx.actor, "live", nil, :regenerate, %{}, "en", now: @now)

    refute share.id == id(1)
    assert share.user_id == ctx.actor.id
    assert share.name == "Leipzig live 1"
    assert share.magic_phrase == "old-fixture-phrase"
    assert share.settings == %{"show_photos" => false, "show_route" => false}
    assert NaiveDateTime.compare(share.expires_at, ~N[2026-10-25 00:00:00]) == :eq

    assert Repo.query!("SELECT id FROM shared_links WHERE id = $1::text::uuid", [id(1)]).rows ==
             []

    assert Repo.query!(
             "SELECT view_count, last_accessed_at FROM shared_links WHERE id = $1::text::uuid",
             [share.id]
           ).rows == [[0, nil]]
  end

  @tag mutation: :phrase
  test "phrase rotation preserves UUID and invalidates old public cookie token", ctx do
    before =
      Repo.query!(
        "SELECT name, settings, created_at FROM shared_links WHERE id = $1::text::uuid",
        [id(1)]
      ).rows

    old_token = DawarichWeb.SharedLinkCookie.unlock_token(id(1), "old-fixture-phrase")

    assert {:ok, %{share: share, committed?: true}} =
             Mutations.run(ctx.actor, "live", nil, :regenerate_phrase, %{}, "en", now: @now)

    assert share.id == id(1)
    refute share.magic_phrase == "old-fixture-phrase"
    assert length(String.split(share.magic_phrase, "-")) == 3
    refute DawarichWeb.SharedLinkCookie.unlock_token(share.id, share.magic_phrase) == old_token

    assert Repo.query!(
             "SELECT name, settings, created_at FROM shared_links WHERE id = $1::text::uuid",
             [id(1)]
           ).rows == before

    assert Repo.query!("SELECT magic_phrase FROM shared_links WHERE id = $1::text::uuid", [id(1)]).rows ==
             [[share.magic_phrase]]
  end

  @tag mutation: :broadcast
  test "live revoke queues old share broadcast atomically but trip does not", ctx do
    assert {:ok, %{committed?: true}} =
             Mutations.run(ctx.actor, "live", nil, :revoke, %{}, "en", now: @now)

    assert commands() == [
             ["share_management.live_revoked", %{"user_id" => ctx.actor.id, "share_id" => id(1)}]
           ]

    assert {:ok, %{committed?: true}} =
             Mutations.run(ctx.actor, "trip", 99101, :revoke, %{}, "en", now: @now)

    assert length(commands()) == 1

    assert Repo.query!(
             "SELECT revoked_at IS NOT NULL FROM shared_links WHERE id IN ($1::text::uuid, $2::text::uuid) ORDER BY id",
             [id(1), id(6)]
           ).rows == [[true], [true]]

    Repo.query!(
      "ALTER TABLE phoenix.rails_commands ADD CONSTRAINT a9_reject_revocation CHECK(kind != 'share_management.live_revoked') NOT VALID"
    )

    before = rows()

    assert_raise Postgrex.Error, fn ->
      Mutations.run(ctx.actor, "live", nil, :revoke, %{}, "en", now: @now)
    end

    assert rows() == before
    assert length(commands()) == 1
    Repo.query!("ALTER TABLE phoenix.rails_commands DROP CONSTRAINT a9_reject_revocation")

    assert {:ok, %{share: share, committed?: true}} =
             Mutations.run(
               ctx.actor,
               "trip",
               99101,
               :create,
               %{"shared_link" => %{"name" => "Trip replacement"}},
               "en",
               now: @now
             )

    assert share.name == "Trip replacement"
    assert share.resource_id == 99101
    before = rows()

    assert {:invalid, %{errors: [{:name, _}]}} =
             Mutations.run(
               ctx.actor,
               "trip",
               99101,
               :create,
               %{"shared_link" => %{"name" => String.duplicate("a", 256)}},
               "en",
               now: @now
             )

    assert rows() == before
    assert length(commands()) == 1

    Repo.query!("UPDATE shared_links SET revoked_at = NULL WHERE id = $1::text::uuid", [id(1)])

    assert {:ok, %{share: live, committed?: true}} =
             Mutations.run(
               ctx.actor,
               "live",
               nil,
               :create,
               %{"shared_link" => %{"name" => "Live replacement"}},
               "en",
               now: @now
             )

    assert live.name == "Live replacement"
    assert live.resource_id == nil

    assert Repo.query!(
             "SELECT revoked_at IS NOT NULL FROM shared_links WHERE id IN ($1::text::uuid, $2::text::uuid) ORDER BY id",
             [id(1), id(2)]
           ).rows == [[true], [true]]

    assert Enum.sort(Enum.map(commands(), fn [_, payload] -> payload["share_id"] end)) ==
             Enum.sort([id(1), id(1), id(2)])

    assert Repo.query!(
             "SELECT id::text FROM shared_links WHERE user_id = $1 AND resource_type = 3 AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at > $2)",
             [ctx.actor.id, DateTime.to_naive(@now)]
           ).rows == [[live.id]]
  end

  @tag mutation: :list_owner
  test "owner scope protects shared list revoke and leaves timeline track to Rails", ctx do
    before = rows()

    for target <- [id(5), id(7)] do
      assert Mutations.run(ctx.actor, "shared", target, :revoke, %{}, "en", now: @now) == :rails
    end

    assert rows() == before
    assert commands() == []

    for target <- [id(8), id(99)] do
      assert Mutations.run(ctx.actor, "shared", target, :revoke, %{}, "en", now: @now) ==
               {:error, 404}
    end

    assert rows() == before

    assert {:ok, %{share: %{id: live_id}, committed?: true}} =
             Mutations.run(ctx.actor, "shared", id(1), :revoke, %{}, "en", now: @now)

    assert live_id == id(1)

    assert {:ok, %{share: %{id: trip_id}, committed?: true}} =
             Mutations.run(ctx.actor, "shared", id(6), :revoke, %{}, "en", now: @now)

    assert trip_id == id(6)

    assert commands() == [
             ["share_management.live_revoked", %{"user_id" => ctx.actor.id, "share_id" => id(1)}]
           ]
  end

  @tag mutation: :missing
  test "missing active link returns Rails fallback destination without changes", ctx do
    for {type, trip_id, target} <- [{"live", nil, id(1)}, {"trip", 99101, id(6)}] do
      assert {:ok, %{committed?: true}} =
               Mutations.run(ctx.actor, type, trip_id, :destroy, %{}, "en", now: @now)

      assert Repo.query!("SELECT id FROM shared_links WHERE id = $1::text::uuid", [target]).rows ==
               []
    end

    assert commands() == []

    Repo.query!("DELETE FROM shared_links WHERE user_id = $1 AND resource_type IN (0, 3)", [
      ctx.actor.id
    ])

    before = rows()

    for {type, trip_id, destination} <- [
          {"live", nil, "/map/v2"},
          {"trip", 99101, "/trips/99101"}
        ],
        action <- [:destroy, :revoke, :regenerate, :regenerate_phrase] do
      assert Mutations.run(ctx.actor, type, trip_id, action, %{}, "en", now: @now) ==
               {:missing, destination}
    end

    assert rows() == before
    assert commands() == []
  end

  defp id(n), do: "a9f10000-0000-4000-8000-" <> String.pad_leading(to_string(n), 12, "0")
  defp rows, do: Repo.query!("SELECT row_to_json(s)::text FROM shared_links s ORDER BY id").rows
end
