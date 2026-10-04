defmodule Dawarich.Digests.SchedulingTest do
  use Dawarich.JobsCase

  alias Dawarich.Digests.Scheduling

  test "digest target periods use the serialized ambient calendar" do
    for row <- corpus()["schedulers"] do
      {:ok, now, 0} = DateTime.from_iso8601(row["now"])
      period = Scheduling.period(ScratchRepo, row["kind"], now, row["ambient_zone"])

      assert period.year == row["period"]["year"], row["id"]
      assert period.month == row["period"]["month"], row["id"]
    end

    now = ~U[2025-01-31 23:30:00Z]
    assert Scheduling.period(ScratchRepo, "monthly", now) == %{year: 2025, month: 1}

    assert Scheduling.period(ScratchRepo, "monthly", now, "Tokyo") ==
             Scheduling.period(ScratchRepo, "monthly", now, "Asia/Tokyo")
  end

  defp corpus do
    __DIR__
    |> Path.join("../../fixtures/a12d1b2/jobs.json")
    |> File.read!()
    |> Jason.decode!()
  end

  test "digest candidates match Rails find_each eligibility across two batches" do
    for row <- corpus()["schedulers"] do
      reset!(ScratchRepo)
      Dawarich.DigestFixtures.load_scheduler!(ScratchRepo, row)
      period = %{year: row["period"]["year"], month: row["period"]["month"]}
      {first, cursor} = Scheduling.batch(ScratchRepo, row["kind"], period, 0)
      {second, next_cursor} = Scheduling.batch(ScratchRepo, row["kind"], period, cursor)
      {[], nil} = Scheduling.batch(ScratchRepo, row["kind"], period, next_cursor || cursor)
      expected = Enum.map(row["jobs"], &hd(&1["arguments"]))

      assert Enum.map(first ++ second, & &1.id) == expected, row["id"]
      assert length(first) <= 1000
      assert Enum.all?(first, &(&1.id <= cursor))
      assert Enum.all?(second, &(&1.id > cursor))

      if String.starts_with?(row["id"], "two_batches") do
        assert length(expected) > 1000
        assert second != []
        assert next_cursor == List.last(row["users"])["id"]
      else
        assert second == []
        assert next_cursor == nil
      end
    end
  end
end
