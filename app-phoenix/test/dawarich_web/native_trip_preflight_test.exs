defmodule DawarichWeb.NativeTripPreflightTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.Test.RailsUser

  test "native data documents reject malformed settings before retained Trip preflight" do
    id = System.unique_integer([:positive])
    RailsUser.insert!(%{id: id, email: "native-form-shape-#{id}@dawarich.test"})
    Repo.query!("UPDATE users SET settings='[]'::jsonb WHERE id=$1", [id], log: false)
    response = DawarichWeb.NativeDataRequest.call(RailsUser.signed_in(id), [])
    assert response.halted
    assert response.status == 422
  end

  test "native trip forms bypass the retired document preflight" do
    user =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "native-form-preflight@dawarich.test"
      })

    conn =
      Plug.Test.conn(:get, "/trips/not-an-id/edit")
      |> Plug.Conn.assign(:current_user, user)
      |> Plug.Conn.put_private(:native_data_document, true)

    response = DawarichWeb.TripDocument.call(conn, [])
    refute response.halted
    assert response.status == nil
  end
end
