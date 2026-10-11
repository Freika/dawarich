defmodule Dawarich.MapApi.BoundsExecutionTest do
  use Dawarich.DataCase, async: false
  alias Dawarich.MapApi.Hexagons

  test "native robust bounds disable JIT only for the bounded cell query" do
    user = %{id: user!(%{settings: %{"timezone" => "UTC"}}), timezone: "UTC"}

    Repo.query!(
      "INSERT INTO points (user_id,timestamp,lonlat,created_at,updated_at) VALUES ($1,1735689600,'SRID=4326;POINT(13 52)',now(),now())",
      [user.id]
    )

    parent = self()
    handler = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler,
      [:dawarich, :repo, :query],
      fn _, _, metadata, _ ->
        if self() == parent and String.starts_with?(metadata.query, "SELECT FLOOR(ST_X") do
          [[enabled]] = Repo.query!("SHOW jit", [], log: false).rows
          send(parent, {:bounds_jit, enabled})
        end
      end,
      nil
    )

    try do
      assert {:ok, :ok} =
               Repo.transaction(fn ->
                 Repo.query!("SET LOCAL jit = on")
                 Repo.query!("SAVEPOINT native_bounds_jit")

                 assert {:ok, %{"point_count" => 1, "min_lat" => 52.0, "max_lng" => 13.0}} =
                          Hexagons.bounds(user, %{
                            "start_date" => "2025-01-01T00:00",
                            "end_date" => "2025-01-01T23:59",
                            "robust" => "true"
                          })

                 assert_receive {:bounds_jit, "off"}
                 Repo.query!("ROLLBACK TO SAVEPOINT native_bounds_jit")
                 assert Repo.query!("SHOW jit").rows == [["on"]]
                 :ok
               end)
    after
      :telemetry.detach(handler)
    end
  end
end
