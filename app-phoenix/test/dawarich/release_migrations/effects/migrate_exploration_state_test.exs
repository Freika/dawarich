defmodule Dawarich.ReleaseMigrations.Effects.MigrateExplorationStateTest do
  use Dawarich.ScratchCase

  alias Dawarich.ReleaseMigrations.Effects.MigrateExplorationState
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.ReleaseMigrations.V1_15_2

  @old ~N[2026-01-01 00:00:00.000000]

  setup do
    scratch_sql!("""
    CREATE TABLE users (id bigserial PRIMARY KEY, deleted_at timestamp);
    CREATE TABLE achievement_progresses (id bigserial PRIMARY KEY, user_id bigint NOT NULL REFERENCES users (id), achievement_key character varying NOT NULL, state jsonb DEFAULT '{}' NOT NULL, sharing_enabled boolean DEFAULT FALSE NOT NULL, sharing_uuid character varying, created_at timestamp(6) NOT NULL, updated_at timestamp(6) NOT NULL);
    CREATE UNIQUE INDEX index_achievement_progresses_on_user_id_and_achievement_key ON achievement_progresses (user_id, achievement_key);
    CREATE UNIQUE INDEX index_achievement_progresses_on_sharing_uuid ON achievement_progresses (sharing_uuid);
    CREATE TABLE user_achievements (id bigserial PRIMARY KEY, user_id bigint NOT NULL REFERENCES users (id), achievement_key character varying NOT NULL, earned_at timestamp(6) NOT NULL, metadata jsonb DEFAULT '{}' NOT NULL, created_at timestamp(6) NOT NULL, updated_at timestamp(6) NOT NULL);
    CREATE UNIQUE INDEX index_user_achievements_on_user_id_and_achievement_key ON user_achievements (user_id, achievement_key);
    INSERT INTO users (deleted_at) VALUES (NULL), (NULL), (NULL), ('2026-01-06');
    """)

    :ok
  end

  test "merges legacy earned timestamps by their bytewise minimum into the exploration row" do
    progress(1, "exploration", %{
      "earned" => %{"DE-BE" => "2026-01-15T00:00:00Z", "PL-MZ" => "2026-01-01T00:00:00Z"},
      "dwell" => %{"DE-BE" => 3},
      "cursor" => 7,
      "calculation_version" => 2
    })

    progress(1, "explorer_germany", %{
      "earned" => %{"DE-BE" => "2026-03-01T00:00:00Z", "IT-25" => "2026-06-01T00:00:00Z"}
    })

    progress(1, "explorer_europe", %{
      "earned" => %{"DE-BE" => "2026-01-10T00:00:00Z", "IT-25" => "2026-06-01T00:00:00.000Z"}
    })

    progress(1, "border_hopper", %{"earned" => %{"PL-MZ" => "2026-05-01T00:00:00Z"}})
    progress(1, "country_fr", %{"earned" => %{"FR-IDF" => "2025-12-01T00:00:00Z"}})

    MigrateExplorationState.run(ScratchRepo)

    assert rows("SELECT achievement_key, state FROM achievement_progresses ORDER BY id") == [
             [
               "exploration",
               %{
                 "earned" => %{
                   "DE-BE" => "2026-01-10T00:00:00Z",
                   "IT-25" => "2026-06-01T00:00:00.000Z",
                   "PL-MZ" => "2026-01-01T00:00:00Z"
                 },
                 "dwell" => %{},
                 "cursor" => 0
               }
             ],
             ["country_fr", %{"earned" => %{"FR-IDF" => "2025-12-01T00:00:00Z"}}]
           ]

    assert NaiveDateTime.compare(
             hd(column("SELECT updated_at FROM achievement_progresses WHERE id = 1")),
             @old
           ) == :gt
  end

  test "creates exploration rows in the order users first appear among the legacy rows" do
    progress(3, "world_traveler", %{"earned" => %{"JP-13" => "2026-02-02T00:00:00Z"}})
    progress(2, "globetrotter", %{"visited" => 3})
    progress(3, "explorer_usa", %{"earned" => %{"US-NY" => "2026-02-03T00:00:00Z"}})

    MigrateExplorationState.run(ScratchRepo)

    assert rows(
             "SELECT id, user_id, state, sharing_enabled, sharing_uuid FROM achievement_progresses ORDER BY id"
           ) == [
             [
               4,
               3,
               %{
                 "earned" => %{
                   "JP-13" => "2026-02-02T00:00:00Z",
                   "US-NY" => "2026-02-03T00:00:00Z"
                 },
                 "dwell" => %{},
                 "cursor" => 0
               },
               false,
               nil
             ],
             [5, 2, %{"earned" => %{}, "dwell" => %{}, "cursor" => 0}, false, nil]
           ]
  end

  test "keeps carriers with their ids and sharing UUIDs, renames them and clears their state" do
    progress(1, "explorer_germany", %{"earned" => %{"DE-BE" => "x"}}, true, "share-de")
    progress(1, "border_hopper", %{"earned" => %{"AT-9" => "y"}}, false, "share-bh")
    progress(1, "explorer_usa", %{"earned" => %{"US-NY" => "z"}}, false, " ")
    progress(1, "explorer_europe", %{}, true, nil)
    progress(1, "world_traveler", %{"earned" => %{}}, false, "")
    progress(1, "globetrotter", %{}, true, "share-gt")

    MigrateExplorationState.run(ScratchRepo)

    assert rows("""
           SELECT id, achievement_key, state, sharing_enabled, sharing_uuid, updated_at > '2026-01-01'
           FROM achievement_progresses WHERE achievement_key <> 'exploration' ORDER BY id
           """) == [
             [1, "country_de", %{}, true, "share-de", true],
             [2, "border_hopper", %{}, false, "share-bh", true],
             [4, "continent_europe", %{}, true, nil, true],
             [6, "globetrotter", %{}, true, "share-gt", false]
           ]
  end

  test "renames awards, or destroys them when the renamed key is already taken" do
    award(1, "explorer_germany")
    award(1, "country_de")
    award(1, "explorer_usa")
    award(2, "explorer_europe")
    award(2, "continent_europe")
    award(4, "explorer_usa")
    award(2, "globetrotter")

    MigrateExplorationState.run(ScratchRepo)

    assert rows("""
           SELECT id, user_id, achievement_key, updated_at > '2026-01-01' FROM user_achievements ORDER BY id
           """) == [
             [2, 1, "country_de", false],
             [3, 1, "country_us", true],
             [5, 2, "continent_europe", false],
             [6, 4, "country_us", true],
             [7, 2, "globetrotter", false]
           ]
  end

  test "changes nothing without legacy work, and a repeat run changes nothing" do
    progress(1, "exploration", %{
      "earned" => %{"DE-BE" => "a"},
      "dwell" => %{"DE-BE" => 2},
      "cursor" => 4
    })

    progress(1, "country_de", %{"earned" => %{"DE-BE" => "a"}}, true, "share-de")
    award(1, "country_de")
    untouched = dump()

    MigrateExplorationState.run(ScratchRepo)
    assert dump() == untouched

    progress(2, "explorer_germany", %{"earned" => %{"DE-BY" => "b"}}, true, "share-legacy")
    progress(2, "border_hopper", %{"earned" => %{"AT-9" => "c"}}, false, "share-bh")
    award(2, "explorer_germany")
    MigrateExplorationState.run(ScratchRepo)
    migrated = dump()

    MigrateExplorationState.run(ScratchRepo)
    assert dump() == migrated
  end

  test "resets a migrated exploration row's dwell and cursor when a kept legacy carrier remains" do
    progress(1, "exploration", %{
      "earned" => %{"PL-MZ" => "a"},
      "dwell" => %{"PL-MZ" => 4},
      "cursor" => 12
    })

    progress(1, "world_traveler", %{}, true, nil)

    MigrateExplorationState.run(ScratchRepo)

    assert rows("SELECT state, updated_at > '2026-01-01' FROM achievement_progresses ORDER BY id") ==
             [
               [%{"earned" => %{"PL-MZ" => "a"}, "dwell" => %{}, "cursor" => 0}, true],
               [%{}, false]
             ]
  end

  test "fails like Rails' validations: a taken carrier key, a soft-deleted user without an exploration row" do
    progress(1, "explorer_germany", %{}, true, "share-de")
    progress(1, "country_de", %{})

    assert_raise Ruby.Error, "Validation failed: Achievement key has already been taken", fn ->
      MigrateExplorationState.run(ScratchRepo)
    end

    scratch_sql!("DELETE FROM achievement_progresses")
    progress(4, "explorer_germany", %{"earned" => %{"DE-BE" => "a"}})

    assert_raise Ruby.Error, "Validation failed: User must exist", fn ->
      MigrateExplorationState.run(ScratchRepo)
    end

    progress(4, "exploration", %{})
    MigrateExplorationState.run(ScratchRepo)

    assert column("SELECT state FROM achievement_progresses") == [
             %{"earned" => %{"DE-BE" => "a"}, "dwell" => %{}, "cursor" => 0}
           ]
  end

  test "raises where Ruby would, and fails as unreproducible where Phoenix cannot match Ruby's error" do
    progress(1, "explorer_germany", %{"earned" => nil})

    assert_raise Ruby.Error, "undefined method 'each' for nil", fn ->
      MigrateExplorationState.run(ScratchRepo)
    end

    scratch_sql!("DELETE FROM achievement_progresses")
    progress(1, "explorer_germany", %{"earned" => %{"DE-BE" => "2026-01-02T00:00:00Z"}})
    progress(1, "explorer_europe", %{"earned" => %{"DE-BE" => 1}})

    assert_raise Ruby.Unreproducible, ~r/cannot reproduce Ruby's comparison/, fn ->
      MigrateExplorationState.run(ScratchRepo)
    end

    scratch_sql!("DELETE FROM achievement_progresses")
    progress(1, "explorer_germany", %{"earned" => ["DE-BE"]})

    assert_raise Ruby.Unreproducible, ~r/cannot reproduce Ruby's each/, fn ->
      MigrateExplorationState.run(ScratchRepo)
    end
  end

  test "writes floats into the exploration state the way Rails' Oj encoder does" do
    scratch_sql!("""
    INSERT INTO achievement_progresses (user_id, achievement_key, state, created_at, updated_at) VALUES
      (1, 'exploration', '{"earned": {"AT-9": 10000000000000000.0}, "dwell": {}, "cursor": 0}', '2026-01-01', '2026-01-01'),
      (1, 'explorer_germany', '{"earned": {"DE-BE": 0.00005}}', '2026-01-01', '2026-01-01'),
      (2, 'explorer_usa', '{"earned": {"US-NY": 1.5, "NL-NH": 1767225600.0}}', '2026-01-01', '2026-01-01')
    """)

    MigrateExplorationState.run(ScratchRepo)

    assert column(
             "SELECT state::text FROM achievement_progresses WHERE achievement_key = 'exploration' ORDER BY user_id"
           ) == [
             ~s({"dwell": {}, "cursor": 0, "earned": {"AT-9": 10000000000000000.0, "DE-BE": 0.00005}}),
             ~s({"dwell": {}, "cursor": 0, "earned": {"NL-NH": 1767225600.0, "US-NY": 1.5}})
           ]
  end

  test "20260720160000 runs the migration whenever achievement_progresses exists" do
    progress(1, "explorer_germany", %{"earned" => %{"DE-BE" => "a"}})
    step().(ScratchRepo)
    assert column("SELECT achievement_key FROM achievement_progresses") == ["exploration"]

    scratch_sql!("DROP TABLE achievement_progresses")
    assert step().(ScratchRepo) == nil
  end

  defp progress(user_id, key, state, sharing_enabled \\ false, sharing_uuid \\ nil) do
    ScratchRepo.query!(
      "INSERT INTO achievement_progresses (user_id, achievement_key, state, sharing_enabled, sharing_uuid, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, '2026-01-01', '2026-01-01')",
      [user_id, key, state, sharing_enabled, sharing_uuid],
      log: false
    )
  end

  defp award(user_id, key) do
    ScratchRepo.query!(
      "INSERT INTO user_achievements (user_id, achievement_key, earned_at, created_at, updated_at) VALUES ($1, $2, '2026-01-02', '2026-01-01', '2026-01-01')",
      [user_id, key],
      log: false
    )
  end

  defp dump do
    {rows("SELECT * FROM achievement_progresses ORDER BY id"),
     rows("SELECT * FROM user_achievements ORDER BY id")}
  end

  defp step, do: V1_15_2.steps() |> List.keyfind("20260720160000", 0) |> elem(1)
  defp rows(sql), do: ScratchRepo.query!(sql, [], log: false).rows
  defp column(sql), do: sql |> rows() |> List.flatten()
end
