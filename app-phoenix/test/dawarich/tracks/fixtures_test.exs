defmodule Dawarich.Tracks.FixturesTest do
  use ExUnit.Case, async: false

  alias Dawarich.Tracks.TracksFixtures

  @tables ~w[users point_sources imports points tracks track_segments]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
  end

  for name <- TracksFixtures.names() do
    @name name

    test "every fixture loads into the scratch database: #{name}" do
      counts = TracksFixtures.input_counts(@name)
      expected = TracksFixtures.load!(Dawarich.Repo, @name)

      assert is_map(expected)

      for table <- @tables do
        ids = Map.fetch!(counts, table)

        %{rows: [[count]]} =
          Dawarich.Repo.query!("SELECT count(*) FROM #{table} WHERE id = ANY($1::bigint[])", [ids])

        assert count == length(ids),
               "expected #{length(ids)} #{table} rows for #{@name}, got #{count}"
      end
    end
  end
end
