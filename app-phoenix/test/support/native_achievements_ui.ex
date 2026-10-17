defmodule Dawarich.Test.NativeAchievementsRouter do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :test_browser do
    plug :fetch_query_params
    plug DawarichWeb.RailsAuth
    plug :fetch_session
    plug :fetch_live_flash
    plug DawarichWeb.Locale
    plug DawarichWeb.LayoutAssigns
  end

  scope "/" do
    pipe_through :test_browser

    live_session :test_achievements,
      session: {DawarichWeb.NativeAuth, :live_session, []},
      on_mount: {DawarichWeb.NativeDataAuth, :require_user},
      root_layout: {DawarichWeb.Layouts, :native_root},
      layout: {DawarichWeb.Layouts, :app} do
      live "/achievements", DawarichWeb.NativeAchievementsLive, :index
      live "/achievements/:key", DawarichWeb.NativeAchievementsLive, :show
    end
  end
end

defmodule Dawarich.Test.NativeAchievementsUI do
  def conn(user, path) do
    conn = Dawarich.Test.NativeAdminUI.conn(user)

    conn = %{
      conn
      | request_path: URI.parse(path).path,
        path_info: String.split(URI.parse(path).path, "/", trim: true),
        query_string: URI.parse(path).query || "",
        secret_key_base: DawarichWeb.Endpoint.config(:secret_key_base)
    }

    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_private(:phoenix_endpoint, DawarichWeb.Endpoint)
    |> Dawarich.Test.NativeAchievementsRouter.call([])
  end
end
