defmodule DawarichWeb.NativeFamilyMapTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  alias Dawarich.{Accounts, Maps, Repo}
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  @endpoint DawarichWeb.Endpoint
  @now FrameSeeds.load_family("consented_map_en")["now"] |> DateTime.from_iso8601() |> elem(1)
  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    owner = FrameSeeds.seed_family!(FrameSeeds.load_family("consented_map_en"))
    %{owner: owner, outsider: Accounts.get(90103)}
  end

  defp read(user, path),
    do:
      RailsUser.signed_in(user.id)
      |> Plug.Conn.assign(:now, @now)
      |> get("/native/map/data/family/" <> path)

  test "native family reads recheck membership and withdrawn sharing", ctx do
    conn = read(ctx.owner, "locations")
    assert conn.status == 200
    assert [%{"user_id" => 90102}] = json_response(conn, 200)["locations"]

    Repo.query!(
      "UPDATE users SET settings = jsonb_set(settings, '{family,location_sharing,enabled}', 'false') WHERE id = 90102"
    )

    assert json_response(read(ctx.owner, "locations"), 200)["locations"] == []

    assert json_response(
             read(ctx.owner, "history?start_at=2026-10-01T00:00:00Z&end_at=2026-10-04T00:00:00Z"),
             200
           )["members"] == []

    assert read(ctx.outsider, "locations").status == 404
    Repo.query!("DELETE FROM family_memberships WHERE user_id = $1", [ctx.owner.id])
    assert read(ctx.owner, "locations").status == 404
  end

  test "family map refuses a consent change during its snapshot", ctx do
    scope = Maps.principal(ctx.owner, "en")

    assert {:error, :grant_changed} =
             Dawarich.Maps.Family.read(scope, :locations, %{},
               now: @now,
               self_hosted: true,
               after_read: fn result ->
                 Repo.query!(
                   "UPDATE users SET settings = jsonb_set(settings, '{family,location_sharing,enabled}', 'false') WHERE id = 90102"
                 )

                 result
               end
             )
  end

  test "family map retains original session admission", ctx do
    scope = Maps.principal(ctx.owner, "en")

    assert {:ok, 200, _} =
             Dawarich.Maps.Family.read(scope, :locations, %{},
               now: @now,
               self_hosted: true
             )

    Repo.query!("UPDATE users SET encrypted_password = 'synthetic-revoked' WHERE id = $1", [
      ctx.owner.id
    ])

    assert {:error, :stale_session} =
             Dawarich.Maps.Family.read(scope, :locations, %{},
               now: @now,
               self_hosted: true
             )
  end
end
