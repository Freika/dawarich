defmodule Dawarich.ReleaseMigrations.V1_13_0Test do
  use Dawarich.ScratchCase

  import Dawarich.ReleaseMigration, only: [index_name?: 3]

  alias Dawarich.RailsTree
  alias Dawarich.ReleaseMigrations.V1_13_0

  @replacement "index_points_on_user_id_timestamp_lonlat"

  setup do
    scratch_sql!(
      ~s|CREATE TABLE points (id bigserial PRIMARY KEY, user_id bigint, "timestamp" integer, lonlat text)|
    )

    scratch_sql!(
      ~s|CREATE INDEX index_points_on_user_id_and_timestamp ON points (user_id, "timestamp" DESC)|
    )

    {_, step, _} = List.keyfind(V1_13_0.steps(), "20260816120000", 0)
    %{step: step}
  end

  test "an invalid replacement index over duplicate rows stops the step with Rails' curated message",
       %{step: step} do
    scratch_sql!(
      ~s|INSERT INTO points (user_id, "timestamp", lonlat) VALUES (1, 1, 'a'), (1, 1, 'a')|
    )

    invalid_unique_index!(@replacement, ~s|(user_id, "timestamp", lonlat)|)

    assert_raise RuntimeError, rails_message(), fn -> step.(ScratchRepo) end
    assert index_name?(ScratchRepo, "points", "index_points_on_user_id_and_timestamp")
  end

  test "every other invalid points index is dropped before the superseded indexes go",
       %{step: step} do
    scratch_sql!(
      ~s|INSERT INTO points (user_id, "timestamp", lonlat) VALUES (1, 1, 'a'), (1, 2, 'a')|
    )

    invalid_unique_index!("index_points_on_user_id_unique", "(user_id)")
    scratch_sql!(~s|CREATE UNIQUE INDEX #{@replacement} ON points (user_id, "timestamp", lonlat)|)

    step.(ScratchRepo)

    refute index_name?(ScratchRepo, "points", "index_points_on_user_id_unique")
    refute index_name?(ScratchRepo, "points", "index_points_on_user_id_and_timestamp")
    assert index_name?(ScratchRepo, "points", @replacement)
  end

  defp invalid_unique_index!(name, columns) do
    assert_raise Postgrex.Error, ~r/unique_violation/, fn ->
      scratch_sql!("CREATE UNIQUE INDEX CONCURRENTLY #{name} ON points #{columns}")
    end
  end

  defp rails_message do
    [_, body] =
      Regex.run(
        ~r/raise ActiveRecord::MigrationError, <<~MESSAGE\n(.*?)\n\s*MESSAGE\n/s,
        RailsTree.read("db/migrate/20260816120000_drop_superseded_points_indexes.rb")
      )

    lines = String.split(body, "\n")

    indent =
      lines
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(&(byte_size(&1) - byte_size(String.trim_leading(&1))))
      |> Enum.min()

    lines
    |> Enum.map_join("\n", &String.slice(&1, indent..-1//1))
    |> String.replace("\#{REPLACEMENT_INDEX}", @replacement)
    |> Kernel.<>("\n")
  end
end
