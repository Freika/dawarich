defmodule DawarichWeb.A8RoutesTest do
  use ExUnit.Case, async: true

  test "existing page routes survive declaration extraction" do
    for {path, module, action, pipelines} <- [
          {"/", DawarichWeb.HomeDispatch, [], [:public_home]},
          {"/settings/general", Phoenix.LiveView.Plug, :index, [:browser, :rails_user]},
          {"/settings/integrations", Phoenix.LiveView.Plug, :index, [:browser, :rails_user]},
          {"/imports/42/download", DawarichWeb.ImportsDownload, :show, [:browser, :rails_user]},
          {"/map/v2", Phoenix.LiveView.Plug, :index, [:browser, :rails_user]},
          {"/map/timeline_feeds", DawarichWeb.MapFrames, :index, [:rails_frame]},
          {"/map/timeline_feeds/calendar", DawarichWeb.MapFrames, :calendar, [:rails_frame]},
          {"/places/42", DawarichWeb.PlaceNavigation, :show, [:rails_frame]}
        ] do
      route = Phoenix.Router.route_info(DawarichWeb.Router, "GET", path, "www.example.com")
      assert %{plug: ^module, plug_opts: ^action, pipe_through: ^pipelines} = route
    end

    route = Phoenix.Router.route_info(DawarichWeb.Router, "GET", "/imports/42", "www.example.com")
    assert route.rails_gate == {DawarichWeb.ImportsGate, :native?}

    assert {DawarichWeb.ImportsLive.Show, :show, _, %{name: :rails_pages}} =
             route.phoenix_live_view
  end
end
