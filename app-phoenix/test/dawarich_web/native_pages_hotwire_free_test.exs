defmodule DawarichWeb.NativePagesHotwireFreeTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Repo
  alias Dawarich.Test.{FrameSeeds, RailsUser}

  @endpoint DawarichWeb.Endpoint
  @markers [
    "type=\"importmap\"",
    "/phoenix/js/",
    "data-turbo",
    "data-controller",
    "data-action=",
    "turbo-frame",
    "turbo-stream",
    "RailsStimulus",
    "rails_bridge",
    " inert",
    "data-rails-form-ready",
    "onclick=",
    "onchange="
  ]
  @sessions [:native_pages, :native_admin, :native_background]
  @secret_free_change_forms ["integration-settings"]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    user = FrameSeeds.user!(8411)
    Repo.query!("UPDATE users SET admin = true WHERE id = 8411")

    Repo.insert_all("tags", [
      %{
        id: 84111,
        user_id: user.id,
        name: "Gate",
        icon: "☕",
        color: "#123abc",
        created_at: ~N[2026-03-01 10:00:00],
        updated_at: ~N[2026-03-01 10:00:00]
      }
    ])

    url = Dawarich.Test.NativeIntegrationStub.start!()
    {:ok, key} = Dawarich.ActiveRecordEncryption.key()

    Repo.insert_all("trip_sources", [
      %{
        id: 84111,
        user_id: user.id,
        provider: "trek",
        base_url: url,
        api_key: Dawarich.ActiveRecordEncryption.encrypt("synthetic-trek", key),
        status: 0,
        importing: false,
        created_at: ~N[2026-03-01 10:00:00],
        updated_at: ~N[2026-03-01 10:00:00]
      }
    ])

    %{user: user}
  end

  defp unlabelled(html) do
    doc = LazyHTML.from_document(html)

    for control <-
          doc
          |> LazyHTML.query(
            "input:not([type=hidden]):not([type=submit]):not([type=button]), select, textarea"
          )
          |> LazyHTML.filter(":not(label *):not([aria-label]):not([aria-labelledby])"),
        id <- [List.first(LazyHTML.attribute(control, "id"))],
        is_nil(id) or Enum.count(LazyHTML.query(doc, ~s(label[for="#{id}"]))) != 1,
        do: LazyHTML.to_html(control)
  end

  defp password_forms_with_change(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("form[phx-change]")
    |> Enum.reject(&(List.first(LazyHTML.attribute(&1, "id")) in @secret_free_change_forms))
    |> Enum.filter(&(LazyHTML.query(&1, "input[type=password]") |> Enum.count() > 0))
  end

  defp native_paths do
    DawarichWeb.Router.__routes__()
    |> Enum.filter(fn
      %{metadata: %{phoenix_live_view: {_, _, _, %{name: name}}}} -> name in @sessions
      _ -> false
    end)
    |> Enum.map(fn %{path: path} ->
      id = if String.starts_with?(path, "/settings/users"), do: "8411", else: "84111"
      String.replace(path, ":id", id)
    end)
  end

  test "native admin and background pages retain exactly one accessible label per control", %{
    user: user
  } do
    previous = Map.new(~w(SELF_HOSTED DAWARICH_RAILS), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "true")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      for {key, value} <- previous,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    RailsUser.insert!(%{
      id: 8412,
      email: "native-label-target@example.invalid",
      api_key: "synthetic-label-target-key",
      settings: %{"timezone" => "UTC"}
    })

    for {actor, path} <- [
          {user.id, "/settings/users"},
          {user.id, "/settings/users/8412"},
          {user.id, "/settings/users/8412/edit"},
          {user.id, "/settings/background_jobs"},
          {8412, "/settings/background_jobs"}
        ] do
      conn = get(RailsUser.signed_in(actor) |> RailsUser.connecting_as(actor), path)
      {:ok, view, connected} = live(conn)
      assert_native_controls(html_response(conn, 200))
      assert_native_controls(connected)

      if path == "/settings/users" do
        render_hook(view, "open_create", %{})
        assert_native_controls(Dawarich.Test.NativeAdminUI.html(view))
        render_hook(view, "open_delete", %{"id" => "8412"})
        assert_native_controls(Dawarich.Test.NativeAdminUI.html(view))
      end

      GenServer.stop(view.pid)
    end
  end

  defp assert_native_controls(html) do
    assert Dawarich.Test.NativeAdminUI.labels(html) == []
    ids = html |> LazyHTML.from_document() |> LazyHTML.query("[id]") |> LazyHTML.attribute("id")
    assert Enum.uniq(ids) == ids
    for marker <- @markers, do: refute(html =~ marker)
  end

  test "every native page renders without Turbo, Stimulus or the importmap", %{user: user} do
    paths =
      native_paths() ++
        for(
          service <- ~w(photoprism airtrail teslamate trek),
          do: "/settings/integrations?service=#{service}"
        ) ++ ["/admin/settings?section=experimental"]

    assert "/tags" in paths

    saving =
      for path <- paths do
        conn = get(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)
        static = html_response(conn, 200)
        {:ok, _view, connected} = live(conn)

        for {html, phase} <- [{static, :static}, {connected, :connected}], marker <- @markers do
          refute html =~ marker, "#{path} (#{phase}) contains #{marker}"
        end

        for html <- [static, connected] do
          assert unlabelled(html) == [], "#{path} has unlabelled or doubly labelled controls"
          assert password_forms_with_change(html) == [], "#{path} sends passwords on phx-change"
        end

        assert static =~ "/native/app"
        assert static =~ ~r/<script[^>]*phx-track-static[^>]*\/native\/app/

        forms = for html <- [static, connected], html =~ ~s(phx-submit="save"), do: html

        for html <- forms,
            do:
              assert(html =~ ~r/<button[^>]*type="submit"[^>]*phx-disable-with/, "#{path} submit")

        forms != []
      end

    assert Enum.count(saving, & &1) >= 2
  end

  test "native map selection and dialog commands retain accessible Hotwire-free controls", %{
    user: user
  } do
    place = FrameSeeds.place!(user.id, 84112, "Cafe")

    visit =
      FrameSeeds.visit!(user.id, 84112, %{
        place_id: place,
        status: 0,
        started_at: ~N[2026-03-30 09:00:00],
        ended_at: ~N[2026-03-30 10:00:00]
      })

    conn =
      RailsUser.signed_in(user.id)
      |> RailsUser.connecting_as(user.id)
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
      |> Map.merge(%{
        request_path: "/map/v2",
        path_info: ["map", "v2"],
        query_string: "start_at=2026-03-30T00:00&end_at=2026-03-30T23:59&panel=timeline"
      })
      |> Plug.Conn.fetch_query_params()
      |> Dawarich.Test.NativeM6IntegrationRouter.call([])

    {:ok, view, _} = live(conn)
    render_async(view, 5000)
    render_hook(view, "timeline:select_day", %{"date" => "2026-03-30"})
    render_hook(view, "timeline:select", %{"id" => to_string(visit)})
    assert_native_controls(render(view))
    render_hook(view, "visits:bulk", %{"action" => "confirm", "ids" => [to_string(visit)]})
    assert_reply(view, %{ok: true})
    render_async(view, 5000)
    render_hook(view, "visit:edit", %{"id" => to_string(visit)})
    view |> form("#native-visit-note-form", note: %{body: "Gate note"}) |> render_submit()
    assert render(view) =~ "Gate note"
    assert_native_controls(render(view))
    render_hook(view, "visit:close", %{})
    render_hook(view, "map:panel", %{"panel" => "settings"})
    assert_native_controls(render(view))
    GenServer.stop(view.pid)
  end

  test "canonical milestone six documents and changed forms retain native accessible controls", %{
    user: user
  } do
    Dawarich.Test.TripsSeeds.trip!(%{
      id: 84112,
      user_id: user.id,
      name: "Native control trip",
      path: [[13.4, 52.5], [13.5, 52.6]],
      started_at: ~N[2026-06-01 00:00:00],
      ended_at: ~N[2026-06-02 23:59:59]
    })

    stamp = NaiveDateTime.utc_now()

    Repo.insert_all("families", [
      %{
        id: 84112,
        creator_id: user.id,
        name: "Control family",
        created_at: stamp,
        updated_at: stamp
      }
    ])

    Repo.insert_all("family_memberships", [
      %{
        id: 84112,
        family_id: 84112,
        user_id: user.id,
        role: 0,
        created_at: stamp,
        updated_at: stamp
      }
    ])

    uuid = Ecto.UUID.generate()

    Repo.insert_all("shared_links", [
      %{
        id: Ecto.UUID.dump!(uuid),
        user_id: user.id,
        resource_type: 0,
        resource_id: 84112,
        name: "Control share",
        settings: %{"show_photos" => false},
        created_at: stamp,
        updated_at: stamp
      }
    ])

    for path <- ["/map", "/map/v2", "/trips/84112", "/family", "/s/#{uuid}"] do
      conn = get(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)
      assert_native_controls(html_response(conn, 200))
      {:ok, view, connected} = live(conn)
      assert_native_controls(connected)

      cond do
        path in ["/map", "/map/v2"] ->
          assert has_element?(view, "#native-map-search[autocomplete=off]")

          for panel <- ["settings", "timeline", "insights", ""] do
            render_hook(view, "map:panel", %{"panel" => panel})
            render_async(view, 5000)
            assert_native_controls(render(view))
          end

        path == "/trips/84112" ->
          render_click(view, "trip:note:edit", %{"day" => "2026-06-01"})
          assert has_element?(view, "#native-trip-note-form textarea[aria-label]")
          assert_native_controls(render(view))
          render_click(view, "trip:note:cancel", %{})
          assert_native_controls(render(view))

        path == "/family" ->
          view
          |> form("#native-family-invite", family_invitation: %{email: ""})
          |> render_submit()

          assert has_element?(view, "[role=alert]")
          assert_native_controls(render(view))

        true ->
          :ok
      end

      GenServer.stop(view.pid)
    end
  end

  test "LiveView event telemetry, which carries raw form params, reaches only LiveView's own logger" do
    for prefix <- [
          [:phoenix, :live_view, :handle_event],
          [:phoenix, :live_component, :handle_event]
        ],
        handler <- :telemetry.list_handlers(prefix) do
      assert match?({Phoenix.LiveView.Logger, _}, handler.id),
             "unexpected #{inspect(handler.id)} on #{inspect(handler.event_name)}"
    end
  end
end
