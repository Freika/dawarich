defmodule Dawarich.Test.SeedIdsTest do
  use Dawarich.DataCase, async: true

  alias Dawarich.Test.SeedIds

  setup do
    Repo.query!("CREATE TEMP TABLE seed_ids_probe (id bigserial PRIMARY KEY)", [], log: false)
    :ok
  end

  defp last_value do
    [[value]] =
      Repo.query!(
        "SELECT pg_sequence_last_value(pg_get_serial_sequence('seed_ids_probe', 'id')::regclass)",
        [],
        log: false
      ).rows

    value
  end

  defp consume(count) do
    Repo.query!(
      "SELECT nextval(pg_get_serial_sequence('seed_ids_probe', 'id')) FROM generate_series(1, $1)",
      [count],
      log: false
    )
  end

  test "ids behind the sequence leave it untouched" do
    consume(40)
    SeedIds.advance!(Repo, "seed_ids_probe", [12, 30])
    assert last_value() == 40
  end

  test "ids ahead of the sequence move it exactly to the largest id" do
    consume(5)
    SeedIds.advance!(Repo, "seed_ids_probe", [70, 64])
    assert last_value() == 70
    SeedIds.advance!(Repo, "seed_ids_probe", [600_000_000])
    assert last_value() == 600_000_000
  end

  test "an unused sequence moves to the largest id" do
    SeedIds.advance!(Repo, "seed_ids_probe", [9])
    assert last_value() == 9
  end
end
