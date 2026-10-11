defmodule DawarichWeb.NativeM6TileContractTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  test "native track tiles preserve Rails default color and owner exclusion" do
    id = System.unique_integer([:positive])
    RailsUser.insert!(%{id: id, email: "native-track-#{id}@dawarich.test"})
    track(id)
    path = "/native/map/data/tiles/tracks/0/0/0?start_at=1700000000&end_at=1800000000"
    conn = RailsUser.signed_in(id) |> get(path)
    assert conn.status == 200
    assert byte_size(conn.resp_body) > 0
    assert :binary.match(conn.resp_body, "#6366F1") != :nomatch
    foreign = System.unique_integer([:positive])
    RailsUser.insert!(%{id: foreign, email: "foreign-track-#{foreign}@dawarich.test"})
    track(foreign)
    assert (RailsUser.signed_in(id) |> get(path)).resp_body == conn.resp_body
  end

  defp track(id) do
    Repo.query!(
      "INSERT INTO tracks (user_id, start_at, end_at, original_path, distance, created_at, updated_at) VALUES ($1, '2025-06-01', '2025-06-02', ST_GeomFromText('LINESTRING(-10 0,10 0)',4326), 1000, NOW(), NOW())",
      [id]
    )
  end
end
