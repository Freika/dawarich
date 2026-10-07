defmodule Dawarich.Tracks.MapMatching.StateTest do
  use Dawarich.DataCase, async: true

  alias Dawarich.Tracks.MapMatching.State

  @statuses %{pending: 0, matched: 1, partial: 2, rejected: 3, skipped: 4, failed: 5}

  test "write!/3 stores every column and leaves lock_version and updated_at unchanged" do
    assert Code.ensure_loaded?(State)
    id = track!()
    before = rows("SELECT lock_version, updated_at FROM tracks WHERE id=$1", [id])
    path = %Geo.MultiLineString{coordinates: [[{13.0, 52.0}, {13.1, 52.1}]], srid: 4326}
    stamp = ~U[2026-10-06 12:00:00.123456Z]

    attrs = %{
      matched_path: path,
      status: :partial,
      digest: "digest",
      data: %{"schema_version" => 1},
      matched_at: stamp
    }

    assert :ok = State.write!(Repo, id, attrs)
    assert State.read(Repo, id) == attrs
    assert rows("SELECT lock_version, updated_at FROM tracks WHERE id=$1", [id]) == before
    assert :ok = State.write!(Repo, id, %{status: :failed})
    assert State.read(Repo, id) == %{attrs | status: :failed}

    assert :ok =
             State.write!(Repo, id, %{
               matched_path: nil,
               status: nil,
               digest: nil,
               data: %{},
               matched_at: nil
             })

    assert State.read(Repo, id) == %{
             matched_path: nil,
             status: nil,
             digest: nil,
             data: %{},
             matched_at: nil
           }

    assert State.read(Repo, -1) == nil
  end

  test "status integers match the Rails enum mapping" do
    assert Code.ensure_loaded?(State)
    assert Ecto.Enum.mappings(State, :status) |> Map.new() == @statuses
    id = track!()

    for {status, integer} <- @statuses do
      assert :ok = State.write!(Repo, id, %{status: status})
      assert rows("SELECT map_matching_status FROM tracks WHERE id=$1", [id]) == [[integer]]
      assert State.read(Repo, id).status == status
    end
  end

  test "result?/1 is true only for matched and partial" do
    assert Code.ensure_loaded?(State)

    for status <- Map.keys(@statuses) ++ [nil] do
      assert State.result?(%{status: status}) == status in [:matched, :partial]
    end
  end

  defp track! do
    [[id]] =
      rows(
        """
        INSERT INTO tracks(user_id, start_at, end_at, original_path, created_at, updated_at, lock_version)
        VALUES($1, '2026-10-06 12:00:00', '2026-10-06 12:01:00',
          ST_GeomFromText('LINESTRING(13 52,13.1 52.1)',4326), now(), now(), 7) RETURNING id
        """,
        [user!()]
      )

    id
  end
end
