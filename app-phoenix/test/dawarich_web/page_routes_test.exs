defmodule DawarichWeb.PageRoutesTest do
  use ExUnit.Case, async: true

  test "native notifications page metadata uses the native jobs session while independent page routes survive extraction" do
    assert Code.ensure_loaded?(DawarichWeb.PageRoutes)
    assert macro_exported?(DawarichWeb.PageRoutes, :page_routes, 0)

    for {path, view, action, params, gate, session} <- [
          {"/notifications", DawarichWeb.NotificationsLive.Index, :index, %{}, nil, :native_jobs},
          {"/notifications/17", DawarichWeb.NotificationsLive.Show, :show, %{"id" => "17"}, nil,
           :native_jobs},
          {"/imports/17", DawarichWeb.ImportsLive.Show, :show, %{"id" => "17"}, nil,
           :native_jobs},
          {"/places", DawarichWeb.PlacesLive.Index, :index, %{}, nil, :native_pages},
          {"/map/v2", DawarichWeb.MapLive.Native, :index, %{}, nil, :native_m6}
        ] do
      route = info(path)

      assert route.pipe_through == [
               if(session == :native_m6, do: :native_m6_browser, else: :browser),
               :rails_user
             ]

      assert route.plug == Phoenix.LiveView.Plug
      assert route.plug_opts == action
      assert route.path_params == params
      assert Map.get(route, :rails_gate) == gate
      assert {^view, ^action, opts, %{name: ^session, extra: extra}} = route.phoenix_live_view
      assert opts[:container] == {:div, class: "contents"}

      if session == :native_m6 do
        assert extra == %{
                 session: {DawarichWeb.MapLiveAuth, :live_session, []},
                 root_layout: {DawarichWeb.Layouts, :native_root},
                 layout: false
               }
      else
        session_module =
          case session do
            :native_jobs -> DawarichWeb.NativeJobsAuth
            :native_pages -> DawarichWeb.NativeAuth
            :rails_map -> DawarichWeb.RailsAuth
          end

        assert extra.session == {session_module, :live_session, []}

        expected =
          case session do
            :native_pages -> {DawarichWeb.NativeAuth, :require_user}
            :native_jobs -> {DawarichWeb.NativeJobsAuth, :require_user}
            :rails_map -> {DawarichWeb.LiveAuth, :default}
          end

        assert Enum.map(extra.on_mount, & &1.id) == [expected]

        layout = if session == :rails_map, do: :map, else: :app

        root =
          case session do
            :rails_map -> :map_root
            :native_pages -> :native_root
            :native_jobs -> :native_root
          end

        assert extra.layout == {DawarichWeb.Layouts, layout}
        assert extra.root_layout == {DawarichWeb.Layouts, root}
      end
    end

    for {path, plug, action, pipelines, params, gate} <- [
          {"/imports/17/download", DawarichWeb.ImportsDownload, :show, [:browser, :rails_user],
           %{"id" => "17"}, nil},
          {"/places/17", DawarichWeb.PlaceNavigation, :show, [:rails_frame], %{"id" => "17"},
           nil},
          {"/map/residency", DawarichWeb.MapFrames, :residency, [:rails_frame], %{}, nil},
          {"/", DawarichWeb.HomeDispatch, [], [:public_home], %{}, nil}
        ] do
      route = info(path)
      assert route.plug == plug
      assert route.plug_opts == action
      assert route.pipe_through == pipelines
      assert route.path_params == params
      assert Map.get(route, :rails_gate) == gate
    end

    details = info("/insights/details")
    assert details.pipe_through == [:native_data_request, :browser, :rails_user]
    assert details.plug == Phoenix.LiveView.Plug
    assert details.plug_opts == :details
    assert details.path_params == %{}
    refute Map.has_key?(details, :rails_gate)

    assert {DawarichWeb.InsightsLive.NativePage, :details, _, %{name: :native_data, extra: extra}} =
             details.phoenix_live_view

    assert extra.session == {DawarichWeb.NativeAuth, :live_session, []}
    assert Enum.map(extra.on_mount, & &1.id) == [{DawarichWeb.NativeDataAuth, :require_user}]
    assert extra.layout == {DawarichWeb.Layouts, :app}
  end

  defp info(path),
    do: Phoenix.Router.route_info(DawarichWeb.Router, "GET", path, "www.example.com")
end
