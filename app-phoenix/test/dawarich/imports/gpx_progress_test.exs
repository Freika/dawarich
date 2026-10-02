defmodule Dawarich.Imports.GpxProgressTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.GpxProgress
  @now ~U[2026-01-15 23:30:00Z]

  setup do
    [[user]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES ('progress@example.test',now(),now()) RETURNING id"
      )

    [[id]] =
      rows(
        "INSERT INTO imports(user_id,name,created_at,updated_at) VALUES ($1,'progress.gpx',now(),now()) RETURNING id",
        [user]
      )

    on_exit(fn -> rows("DELETE FROM imports WHERE id=$1", [id]) end)
    %{import: %{id: id, user_id: user}, ctx: %{repo: ScratchRepo, locale: "de", now: @now}}
  end

  defp record(c, index, state, now \\ @now),
    do: GpxProgress.record(c.import, index, state, %{c.ctx | now: now})

  defp processed(c), do: rows("SELECT processed FROM imports WHERE id=$1", [c.import.id])

  defp pending,
    do:
      rows("SELECT payload FROM phoenix.rails_commands WHERE kind='imports.progress' ORDER BY id")

  test "native subscribers see committed progress and suppressed updates stay quiet", c do
    Dawarich.Imports.Events.subscribe(c.import.user_id)
    state = record(c, 1000, %{at: nil, index: nil})
    assert_receive :imports_changed
    assert processed(c) == [[1000]]
    assert record(c, 1050, state) == state
    refute_receive :imports_changed
  end

  test "initial, 100-delta and five-second progress use batch inserted count", c do
    state = record(c, 1000, %{at: nil, index: nil})
    assert processed(c) == [[1000]]
    assert record(c, 1050, state) == state
    assert processed(c) == [[1000]]
    state = record(c, 1100, state)
    assert processed(c) == [[1100]]
    assert record(c, 1, state, DateTime.add(@now, 4)) == state
    state = record(c, 1, state, DateTime.add(@now, 5))
    assert state.index == 1
    assert processed(c) == [[1]]
    assert length(pending()) == 3
  end

  test "zero always broadcasts even at unchanged clock and count", c do
    state = record(c, 0, %{at: nil, index: nil})
    record(c, 0, state)
    assert processed(c) == [[0]]
    assert length(pending()) == 2
  end

  test "progress transport failure is best-effort but database progress remains", c do
    rows(
      "CREATE FUNCTION progress_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.kind='imports.progress' THEN RAISE EXCEPTION 'owned progress transport failure'; END IF; RETURN NEW; END $$"
    )

    rows(
      "CREATE TRIGGER progress_fail BEFORE INSERT ON phoenix.rails_commands FOR EACH ROW EXECUTE FUNCTION progress_fail()"
    )

    on_exit(fn ->
      rows("DROP TRIGGER progress_fail ON phoenix.rails_commands")
      rows("DROP FUNCTION progress_fail()")
    end)

    assert %{index: 1000} = record(c, 1000, %{at: nil, index: nil})
    assert processed(c) == [[1000]]
    assert pending() == []
  end
end
