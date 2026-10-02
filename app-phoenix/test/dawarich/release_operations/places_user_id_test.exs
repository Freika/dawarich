defmodule Dawarich.ReleaseOperations.PlacesUserIdTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.ReleaseOperations.PlacesUserId
  alias Dawarich.Wave6Fixtures

  setup do: Wave6Fixtures.reset!()

  test "delegates to the C3a core" do
    user = Wave6Fixtures.user!()
    now = ~N[2020-06-01 10:00:00.000000]

    place =
      Wave6Fixtures.insert!("places", %{
        "name" => "Zoo Leipzig",
        "user_id" => user,
        "latitude" => Decimal.new("51.349700"),
        "longitude" => Decimal.new("12.369400"),
        "created_at" => now,
        "updated_at" => now
      })

    assert PlacesUserId.perform(%Oban.Job{args: %{"version" => 1}}) == :ok
    assert rows("SELECT id, user_id, updated_at FROM places") == [[place, user, now]]

    assert PlacesUserId.perform(%Oban.Job{args: %{"version" => 2}}) ==
             {:cancel, :unsupported_version}
  end
end
