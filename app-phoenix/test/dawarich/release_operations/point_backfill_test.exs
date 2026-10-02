defmodule Dawarich.ReleaseOperations.PointBackfillTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.{ReleaseOperations, Wave6Fixtures}
  alias Dawarich.ReleaseOperations.PointBackfill

  @oban Dawarich.ReleaseOperations.PointBackfillTest.Oban
  @short "SELECT set_config('lock_timeout', '10s', true), set_config('statement_timeout', '100ms', true)"
  @short_lock "SELECT set_config('lock_timeout', '100ms', true), set_config('statement_timeout', '10s', true)"

  setup do
    Wave6Fixtures.reset!()
    start_oban(@oban)
    %{user: Wave6Fixtures.user!()}
  end

  test "SQL fragments and aliases equal Rails'" do
    sql = Wave6Fixtures.load!("sql_fragments")
    extractors = Wave6Fixtures.load!("extractors")

    assert squish(PointBackfill.digest_sql(:points)) == squish(sql["digest_points"])
    assert squish(PointBackfill.digest_sql(:p)) == squish(sql["digest_p"])
    assert squish(PointBackfill.column_list()) == squish(sql["combo_column_list"])
    assert Enum.map(PointBackfill.aliases(), &Tuple.to_list/1) == extractors["country_aliases"]
  end

  test "a dimensions page seeds, stamps only NULL sources, pauses 5 s and continues", %{
    user: user
  } do
    foreign =
      Wave6Fixtures.insert!("point_sources", %{
        "digest" => String.duplicate("f", 32),
        "created_at" => NaiveDateTime.utc_now(),
        "updated_at" => NaiveDateTime.utc_now()
      })

    Wave6Fixtures.point!(user, %{"id" => 1, "tracker_id" => "phone", "topic" => "owntracks/a"})

    Wave6Fixtures.point!(user, %{
      "id" => 2,
      "tracker_id" => "watch",
      "battery_status" => 2,
      "source_id" => foreign
    })

    Wave6Fixtures.point!(user, %{"id" => 3, "tracker_id" => "phone", "topic" => "owntracks/a"})

    {id, result} = run(cursor("dimensions", nil, 2, false))

    assert result == :ok

    assert rows("SELECT digest FROM point_sources ORDER BY digest") ==
             Enum.sort([[String.duplicate("f", 32)] | point_digests([1, 2])])

    assert rows("""
           SELECT p.id, ps.digest = #{PointBackfill.digest_sql(:p)}
           FROM points p JOIN point_sources ps ON ps.id = p.source_id ORDER BY p.id
           """) == [[1, true], [2, false]]

    assert rows("SELECT source_id FROM points WHERE id = 2") == [[foreign]]
    assert rows("SELECT source_id FROM points WHERE id = 3") == [[nil]]
    assert operation(id) == [[cursor("dimensions", 3, 50_000, false), "running"]]

    assert [[args, delay]] = jobs()
    assert args == successor(id, cursor("dimensions", 3, 50_000, false))
    assert delay >= 4 and delay <= 6
  end

  test "the last dimensions page starts country with repair and no pause", %{user: user} do
    Wave6Fixtures.point!(user, %{"id" => 1})
    Wave6Fixtures.point!(user, %{"id" => 2})

    {id, :ok} = run(cursor("dimensions", 1, 50_000, false))

    assert [[args, delay]] = jobs()
    assert args == successor(id, cursor("country", nil, 50_000, true))
    assert delay < 1
  end

  test "country resolves names and aliases to the lowest id and leaves unknown names NULL", %{
    user: user
  } do
    germany = country!("Germany", "DE", "DEU")
    country!("Germany", "DE", "DEU")
    usa = country!("United States of America", "US", "USA")
    named = Wave6Fixtures.point!(user, %{"country_name" => "Germany"})
    aliased = Wave6Fixtures.point!(user, %{"country_name" => "United States"})
    unknown = Wave6Fixtures.point!(user, %{"country_name" => "Atlantis"})

    {id, :ok} = run(cursor("country", nil, 50_000, false))

    assert country_ids([named, aliased, unknown]) == [germany, usa, nil]
    assert status(id) == "completed"
    assert jobs() == []
  end

  test "repair_collisions reassigns an iso_a2 collision only when repairing", %{user: user} do
    kosovo = country!("Kosovo", "XK", "XKX")
    republic = country!("Republic of Kosovo", "XK", "KOS")

    point =
      Wave6Fixtures.point!(user, %{"country_id" => republic, "country_name" => "Kosovo"})

    {_id, :ok} = run(cursor("country", nil, 50_000, false))
    assert country_ids([point]) == [republic]

    {_id, :ok} = run(cursor("country", nil, 50_000, true))
    assert country_ids([point]) == [kosovo]
  end

  test "a statement timeout halves the batch from the same cursor", %{user: user} do
    Wave6Fixtures.point!(user, %{"id" => 1})
    holder = lock_point_sources!()

    {id, result} = run(cursor("dimensions", 1, 10_000, false), bounded: @short)
    release!(holder)

    assert result == :ok
    assert operation(id) == [[cursor("dimensions", 1, 5_000, false), "running"]]
    assert [[args, delay]] = jobs()
    assert args == successor(id, cursor("dimensions", 1, 5_000, false))
    assert delay >= 4 and delay <= 6
    assert rows("SELECT source_id FROM points") == [[nil]]
    assert rows("SELECT count(*) FROM point_sources") == [[0]]
  end

  test "a batch that cannot halve re-raises", %{user: user} do
    Wave6Fixtures.point!(user, %{"id" => 1})
    holder = lock_point_sources!()

    try do
      assert_raise Postgrex.Error, fn ->
        run(cursor("dimensions", 1, 9_999, false), bounded: @short)
      end
    after
      release!(holder)
    end

    assert jobs() == []
  end

  test "a lock timeout re-raises for the retry instead of halving", %{user: user} do
    Wave6Fixtures.point!(user, %{"id" => 1})
    holder = lock_point_sources!()

    try do
      error =
        assert_raise Postgrex.Error, fn ->
          run(cursor("dimensions", 1, 10_000, false), bounded: @short_lock)
        end

      assert error.postgres.code == :lock_not_available
    after
      release!(holder)
    end

    assert jobs() == []

    assert rows("SELECT cursor FROM phoenix.release_operations") == [
             [cursor("dimensions", 1, 10_000, false)]
           ]
  end

  test "a country page that is not the last keeps the phase and the repair flag", %{user: user} do
    germany = country!("Germany", "DE", "DEU")
    for id <- 1..3, do: Wave6Fixtures.point!(user, %{"id" => id, "country_name" => "Germany"})

    {id, :ok} = run(cursor("country", 1, 2, true))

    assert country_ids([1, 2, 3]) == [germany, germany, nil]
    assert operation(id) == [[cursor("country", 3, 50_000, true), "running"]]
    assert [[args, delay]] = jobs()
    assert args == successor(id, cursor("country", 3, 50_000, true))
    assert delay >= 4 and delay <= 6
  end

  test "a statement timeout in the country phase halves and keeps the phase", %{user: user} do
    country!("Germany", "DE", "DEU")
    Wave6Fixtures.point!(user, %{"id" => 1, "country_name" => "Germany"})
    holder = hold!("SELECT id FROM points WHERE id = 1 FOR UPDATE")

    {id, result} = run(cursor("country", 1, 10_000, true), bounded: @short)
    release!(holder)

    assert result == :ok
    assert operation(id) == [[cursor("country", 1, 5_000, true), "running"]]
    assert [[args, _delay]] = jobs()
    assert args == successor(id, cursor("country", 1, 5_000, true))
    assert country_ids([1]) == [nil]
  end

  test "the job timeout outlasts both bounded statements of a page" do
    assert PointBackfill.timeout(%Oban.Job{}) > 2 * :timer.minutes(5)
  end

  test "an empty table completes without a country phase" do
    {id, :ok} = run(cursor("dimensions", nil, 50_000, false))

    assert status(id) == "completed"
    assert jobs() == []
  end

  test "decodes version 1 payloads exactly" do
    payload = cursor("dimensions", nil, 50_000, false)

    assert PointBackfill.args_from_command(1, payload) ==
             {:ok, %{"version" => 1, "cursor" => payload}}

    assert PointBackfill.args_from_command(1, %{payload | "start_id" => 7}) ==
             {:ok, %{"version" => 1, "cursor" => %{payload | "start_id" => 7}}}

    for invalid <- [
          Map.put(payload, "extra", 1),
          %{payload | "start_id" => "1"},
          %{payload | "batch_size" => 0},
          %{payload | "phase" => "other"},
          %{payload | "repair_collisions" => "true"},
          Map.delete(payload, "repair_collisions")
        ] do
      assert PointBackfill.args_from_command(1, invalid) == {:error, "invalid_payload"}
    end

    assert PointBackfill.args_from_command(2, payload) == {:error, "unsupported_version"}
  end

  defp run(cursor, opts \\ []) do
    id = Ecto.UUID.generate()

    job = %Oban.Job{
      args: %{"version" => 1, "event_id" => id, "cursor" => cursor},
      attempt: 1,
      max_attempts: 10
    }

    {id, ReleaseOperations.run(ScratchRepo, @oban, PointBackfill, job, opts)}
  end

  defp cursor(phase, start, size, repair),
    do: %{
      "phase" => phase,
      "start_id" => start,
      "batch_size" => size,
      "repair_collisions" => repair
    }

  defp successor(id, cursor), do: %{"version" => 1, "operation_id" => id, "cursor" => cursor}

  defp country!(name, iso_a2, iso_a3) do
    now = NaiveDateTime.utc_now()

    Wave6Fixtures.insert!("countries", %{
      "name" => name,
      "iso_a2" => iso_a2,
      "iso_a3" => iso_a3,
      "created_at" => now,
      "updated_at" => now
    })
  end

  defp country_ids(ids) do
    Enum.map(ids, fn id ->
      [[country_id]] = rows("SELECT country_id FROM points WHERE id = $1", [id])
      country_id
    end)
  end

  defp point_digests(ids),
    do:
      rows(
        "SELECT DISTINCT #{PointBackfill.digest_sql(:points)} FROM points WHERE id = ANY($1)",
        [ids]
      )

  defp lock_point_sources!, do: hold!("LOCK TABLE point_sources IN EXCLUSIVE MODE")

  defp hold!(sql) do
    parent = self()

    holder =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          ScratchRepo.query!(sql)
          send(parent, :locked)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :locked, 5_000
    holder
  end

  defp release!(holder) do
    send(holder.pid, :release)
    Task.await(holder)
  end

  defp operation(id),
    do:
      rows("SELECT cursor, status FROM phoenix.release_operations WHERE id = $1", [
        Ecto.UUID.dump!(id)
      ])

  defp status(id) do
    [[status]] =
      rows("SELECT status FROM phoenix.release_operations WHERE id = $1", [Ecto.UUID.dump!(id)])

    status
  end

  defp jobs,
    do:
      rows(
        "SELECT args, extract(epoch FROM scheduled_at - inserted_at)::float FROM oban.oban_jobs ORDER BY id"
      )

  defp squish(sql), do: sql |> String.split() |> Enum.join(" ")
end
