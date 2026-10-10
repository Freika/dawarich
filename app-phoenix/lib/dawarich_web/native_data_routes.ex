defmodule DawarichWeb.NativeDataRoutes do
  @moduledoc false
  defmacro native_data_routes do
    quote do
      scope "/" do
        pipe_through [:browser, :rails_user]

        live_session :native_data,
          session: {DawarichWeb.NativeAuth, :live_session, []},
          on_mount: {DawarichWeb.NativeDataAuth, :require_user},
          root_layout: {DawarichWeb.Layouts, :native_root},
          layout: {DawarichWeb.Layouts, :app} do
          live "/points", DawarichWeb.PointsLive.Index, :index,
            container: {:div, class: "contents"}
        end
      end
    end
  end
end
