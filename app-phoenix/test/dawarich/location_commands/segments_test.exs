defmodule Dawarich.LocationCommands.SegmentsTest do
  use Dawarich.IngestCase, async: false
  alias Dawarich.{Accounts, Maps}
  alias Dawarich.LocationCommands.Segments
  alias Dawarich.Test.{ApiGolden, FrameSeeds, RailsUser}

  @now ~U[2026-10-03 10:00:00.000000Z]

  test "segment mode reset preserves recomputation and transaction rollback" do
    ctx = reset_fixture("reset_preserved")
    scope = Maps.principal(Accounts.get(ctx.user.id), "en")
    before = snapshot()

    Repo.query!(
      "CREATE FUNCTION m6b_segment_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic segment write failure'; END $$"
    )

    Repo.query!(
      "CREATE TRIGGER m6b_segment_fault BEFORE INSERT ON track_segments FOR EACH ROW EXECUTE FUNCTION m6b_segment_fault()"
    )

    assert {:error, :reprocess_failed} =
             Segments.reset(scope, ctx.track, ctx.segment, now: ctx.now)

    assert snapshot() == before
    assert commands() == []
    Repo.query!("DROP TRIGGER m6b_segment_fault ON track_segments")
    Repo.query!("DROP FUNCTION m6b_segment_fault()")

    assert {:ok, %{reset: true, page: %{segments: segments}}} =
             Segments.reset(scope, ctx.track, ctx.segment, now: ctx.now)

    refute Enum.any?(segments, &(&1.id == ctx.segment))
    assert Enum.any?(segments, &(&1.id >= ctx.segment + 5))
    assert {:ok, %{segments: listed}} = Segments.list(scope, ctx.track)
    assert Enum.map(listed, & &1.id) == Enum.map(segments, & &1.id)
  end

  test "foreign segment and stale actor cannot enqueue effects" do
    user =
      FrameSeeds.user!(91971, %{
        "timezone" => "UTC",
        "enabled_transportation_modes" => ~w(walking cycling driving)
      })

    foreign = FrameSeeds.user!(91972)

    for {actor, id} <- [{user, 919_710}, {user, 919_711}, {foreign, 919_720}] do
      FrameSeeds.track!(actor.id, id, %{
        start_at: NaiveDateTime.add(~N[2026-10-03 09:00:00], id - 919_710),
        end_at: NaiveDateTime.add(~N[2026-10-03 09:10:00], id - 919_710),
        dominant_mode: 4
      })

      FrameSeeds.segment!(id, id * 10, %{
        start_at: ~U[2026-10-03 09:00:00Z],
        end_at: ~U[2026-10-03 09:10:00Z],
        distance: 1000,
        duration: 600,
        avg_speed: 6.0,
        transportation_mode: 4,
        source: "inferred",
        confidence: 1,
        confidence_score: 0.7
      })
    end

    scope = Maps.principal(user, "en")
    before = snapshot()

    for {track, segment} <- [{919_720, 9_197_200}, {919_710, 9_197_200}, {919_710, 9_197_110}] do
      assert {:error, :not_found} = Segments.override(scope, track, segment, "walking", now: @now)
      assert {:error, :not_found} = Segments.reset(scope, track, segment, now: @now)
    end

    assert {:error, :not_found} = Segments.list(scope, 919_720)

    assert {:error, :mode_not_enabled} =
             Segments.override(scope, 919_710, 9_197_100, "flying", now: @now)

    assert snapshot() == before
    assert commands() == []

    Repo.query!("UPDATE users SET encrypted_password=$1 WHERE id=$2", [
      String.duplicate("rotated", 10),
      user.id
    ])

    assert {:error, :stale_session} =
             Segments.override(scope, 919_710, 9_197_100, "walking", now: @now)

    assert snapshot() == before
    assert commands() == []

    fresh = Maps.principal(Accounts.get(user.id), "en")

    assert {:ok, %{track: %{dominant_mode: "walking"}}} =
             Segments.override(fresh, 919_710, 9_197_100, "walking", now: @now)

    assert [["tracks_changed", %{"updated" => [919_710]}]] = commands()
  end

  defp snapshot do
    for table <- ~w(tracks track_segments),
        do: Repo.query!("SELECT to_jsonb(t)::text FROM #{table} t ORDER BY id").rows
  end

  defp reset_fixture(name) do
    Dawarich.FixtureCleanup.delete!(Repo, ~w(users tracks track_segments points))
    state = File.read!("test/fixtures/map_writes/segments/#{name}.json") |> Jason.decode!()

    user =
      RailsUser.insert!(%{
        id: state["user"]["id"],
        email: "m6b-reset@example.invalid",
        settings: state["user"]["settings"]
      })

    for id <- state["before"]["tracks"] |> Enum.map(& &1["user_id"]) |> Enum.uniq(),
        id != user.id,
        do: RailsUser.insert!(%{id: id, email: "m6b-reset-#{id}@example.invalid"})

    for table <- ~w(tracks track_segments points), row <- state["before"][table] do
      row =
        if is_map(row["original_path"]) do
          [[hex]] =
            Repo.query!("SELECT encode(ST_AsEWKB(ST_GeomFromGeoJSON($1)), 'hex')", [
              Jason.encode!(row["original_path"])
            ]).rows

          Map.put(row, "original_path", hex)
        else
          row
        end

      ApiGolden.insert!(table, row)
    end

    [_, track, segment] = Regex.run(~r{/tracks/(\d+)/segments/(\d+)}, state["request"]["path"])
    {track, segment} = {String.to_integer(track), String.to_integer(segment)}

    Repo.query!("SELECT setval(pg_get_serial_sequence('track_segments','id'), $1, false)", [
      segment + 5
    ])

    {:ok, now, _} = DateTime.from_iso8601(state["now"])
    %{user: user, track: track, segment: segment, now: now}
  end
end
