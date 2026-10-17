defmodule DawarichWeb.NativeM6CloudLinksTest do
  use Dawarich.DataCase
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  setup do
    previous = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", Base.encode64(:crypto.strong_rand_bytes(32)))

    on_exit(fn ->
      if previous,
        do: System.put_env("JWT_SECRET_KEY", previous),
        else: System.delete_env("JWT_SECRET_KEY")
    end)

    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "m6-cloud-links-#{id}@dawarich.test",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    %{id: id}
  end

  test "native Cloud links retain source destinations and stay absent when self hosted", %{id: id} do
    {:ok, cloud, _} = open(id, "/map/v2", "en", false)
    cloud |> element("[data-testid=map-button-links]") |> render_click()
    assert has_element?(cloud, "#native-map-links")

    for href <- [
          "https://discord.gg/pHsBjpt5J8",
          "https://dawarich.app/docs/intro",
          "https://dawarich.app/privacy-policy"
        ] do
      assert has_element?(
               cloud,
               "#native-map-links a[href='#{href}'][target='_blank'][rel='noopener noreferrer']"
             )
    end

    {:ok, local, _} = open(id, "/map/v2?panel=links", "en", true)
    refute has_element?(local, "[data-testid=map-button-links]")
    refute has_element?(local, "#native-map-links")
  end

  defp open(id, path, locale, self_hosted) do
    RailsUser.signed_in(id)
    |> RailsUser.connecting_as(id)
    |> Plug.Conn.assign(:locale, locale)
    |> Plug.Conn.assign(:self_hosted, self_hosted)
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
    |> Map.merge(%{
      request_path: "/map/v2",
      path_info: ["map", "v2"],
      query_string: URI.parse(path).query || ""
    })
    |> Plug.Conn.fetch_query_params()
    |> Dawarich.Test.NativeM6IntegrationRouter.call([])
    |> live()
  end
end
