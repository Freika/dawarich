defmodule Dawarich.ReleaseOperations.RouteOpacityTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.ReleaseOperations.RouteOpacity
  alias Dawarich.Wave6Fixtures

  setup do: Wave6Fixtures.reset!()

  test "divides opacity above 1 by 100 for live users only; a rerun changes nothing" do
    percent = Wave6Fixtures.user!(%{"settings" => %{"route_opacity" => 50}})
    fraction = Wave6Fixtures.user!(%{"settings" => %{"route_opacity" => 0.8}})
    unset = Wave6Fixtures.user!(%{"settings" => %{"theme" => "dark"}})

    deleted =
      Wave6Fixtures.user!(%{
        "settings" => %{"route_opacity" => 50},
        "deleted_at" => NaiveDateTime.utc_now()
      })

    assert RouteOpacity.perform(%Oban.Job{args: %{"version" => 1}}) == :ok
    assert opacities([percent, fraction, unset, deleted]) == [0.5, 0.8, nil, 50]

    assert RouteOpacity.run(ScratchRepo) == :ok
    assert opacities([percent]) == [0.5]
  end

  test "perform cancels an unsupported version" do
    assert RouteOpacity.perform(%Oban.Job{args: %{"version" => 2}}) ==
             {:cancel, :unsupported_version}
  end

  defp opacities(ids) do
    Enum.map(ids, fn id ->
      [[opacity]] = rows("SELECT settings->'route_opacity' FROM users WHERE id = $1", [id])
      opacity
    end)
  end
end
