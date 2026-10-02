defmodule Dawarich.ReleaseOperations.OnboardingCompletedTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.ReleaseOperations.OnboardingCompleted
  alias Dawarich.Wave6Fixtures

  setup do: Wave6Fixtures.reset!()

  test "sets the flag for live users with points and no flag" do
    with_points = Wave6Fixtures.user!(%{"points_count" => 3})

    declined =
      Wave6Fixtures.user!(%{
        "points_count" => 3,
        "settings" => %{"onboarding_completed" => false}
      })

    empty = Wave6Fixtures.user!(%{"points_count" => 0})

    deleted =
      Wave6Fixtures.user!(%{"points_count" => 3, "deleted_at" => NaiveDateTime.utc_now()})

    assert OnboardingCompleted.perform(%Oban.Job{args: %{"version" => 1}}) == :ok

    assert flags([with_points, declined, empty, deleted]) == [true, false, nil, nil]
  end

  test "perform cancels an unsupported version" do
    assert OnboardingCompleted.perform(%Oban.Job{args: %{"version" => 2}}) ==
             {:cancel, :unsupported_version}
  end

  defp flags(ids) do
    Enum.map(ids, fn id ->
      [[flag]] = rows("SELECT settings->'onboarding_completed' FROM users WHERE id = $1", [id])
      flag
    end)
  end
end
