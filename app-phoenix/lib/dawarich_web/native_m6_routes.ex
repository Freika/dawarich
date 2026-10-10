defmodule DawarichWeb.NativeM6Routes do
  @moduledoc false
  defmacro native_m6_routes do
    quote do
      scope "/" do
        pipe_through [:browser, :rails_user]

        live_session :native_m6,
          session: {DawarichWeb.MapLiveAuth, :live_session, []},
          root_layout: {DawarichWeb.Layouts, :native_root},
          layout: false do
          live "/map", DawarichWeb.MapLive.Native, :index, container: {:div, class: "contents"}
          live "/map/v2", DawarichWeb.MapLive.Native, :index, container: {:div, class: "contents"}
        end
      end
    end
  end
end
