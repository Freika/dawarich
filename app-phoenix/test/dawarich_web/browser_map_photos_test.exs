defmodule DawarichWeb.BrowserMapPhotosTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  import Plug.Conn

  test "unconfigured browser photos expose a typed integration outcome without credentials" do
    id = System.unique_integer([:positive])

    user =
      Dawarich.Test.RailsUser.insert!(%{
        id: id,
        email: "browser-photo-#{id}@dawarich.test",
        settings: %{"timezone" => "UTC"}
      })

    conn =
      build_conn()
      |> DawarichWeb.Api.Respond.prepare()
      |> assign(:api_user, user)
      |> assign(:api_params, %{"page" => "1", "per_page" => "100"})
      |> DawarichWeb.BrowserMapPhotos.call()

    assert conn.status == 401
    assert Jason.decode!(conn.resp_body)["code"] == "photos_unconfigured"
    refute conn.resp_body =~ "api_key"
  end
end
