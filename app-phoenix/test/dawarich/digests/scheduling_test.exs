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
end
