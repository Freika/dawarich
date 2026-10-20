defmodule DawarichWeb.NativePagesHotwireFreeTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Repo
  alias Dawarich.Test.{FrameSeeds, RailsUser, ImportsExportsSeeds}

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
  @sessions [
    :native_pages,
    :native_admin,
    :native_background,
    :native_places,
    :native_jobs,
    :native_notifications,
    :native_data
  ]
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

    Dawarich.Test.StatsSeeds.digest!(user.id, %{year: 2024})
    FrameSeeds.stat!(user.id, 2024, 3)

    ImportsExportsSeeds.import!(%{
      id: 84111,
      user_id: user.id,
      raw_data: %{"waypoints_seen" => 1}
    })

    ImportsExportsSeeds.export!(%{id: 84111, user_id: user.id})
    stamp = ~N[2026-03-01 10:00:00]

    Repo.insert_all("notifications", [
      %{
        id: 84111,
        user_id: user.id,
        kind: 0,
        title: "Native structural gate",
        content: "Synthetic safe content",
        created_at: stamp,
        updated_at: stamp
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

      path
      |> String.replace(":id", id)
      |> String.replace(":year", "2024")
      |> String.replace(":month", "3")
      |> String.replace(":key", "country_de")
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

    for marker <- @markers do
      present = String.contains?(html, marker)
      refute present, "legacy marker #{marker}"
    end
  end

  test "all native document roots expose accessible controls without legacy hooks", %{user: user} do
    Dawarich.State.put_registration_enabled(Repo, true)
    previous = Map.new(~w(SELF_HOSTED DAWARICH_RAILS), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "true")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      for {key, value} <- previous,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    for locale <- ~w(en de),
        {actor, path, entry} <- [
          {nil, "/users/sign_in", "/native/auth_http"},
          {nil, "/users/password/new", "/native/auth_http"},
          {user.id, "/tags", "/native/app"},
          {user.id, "/settings/users", "/native/app"},
          {user.id, "/map/v2", "/native/app"}
        ] do
      conn =
        if actor do
          RailsUser.signed_in(actor)
        else
          session = %{"locale" => locale, "_csrf_token" => DawarichWeb.RailsCsrf.new_token()}
          put_req_cookie(build_conn(), "_dawarich_session", RailsUser.cookie(session))
        end

      uri = if actor, do: path <> "?locale=" <> locale, else: path
      response = get(conn, uri)
      status = response.status
      assert status == 200, "document status for #{path} #{locale}"
      html = html_response(response, 200)
      assert_native_controls(html)
      entry_present = String.contains?(html, entry)
      locale_present = String.contains?(html, ~s(lang="#{locale}"))
      assert entry_present, "native entry for #{path}"
      assert locale_present, "document locale for #{path}"
    end
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
        assert conn.status == 200, path
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

  test "native job pages and open dialogs have one accessible label and no Hotwire runtime", %{
    user: user
  } do
    paths = native_paths()

    for path <-
          ~w(/imports /imports/new /imports/84111 /imports/84111/edit /exports /notifications /notifications/84111),
        do: assert(path in paths)

    for locale <- ~w(en de),
        path <-
          ~w(/imports /imports/new /imports/84111 /imports/84111/edit /exports /notifications /notifications/84111) do
      conn =
        get(
          RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id),
          path <> "?locale=" <> locale
        )

      {:ok, view, connected} = live(conn)
      for html <- [html_response(conn, 200), connected], do: assert_native_controls(html)

      events =
        case path do
          "/exports" ->
            {"choose_export_delete", %{"id" => "84111"}, "cancel_export_delete",
             "export-delete-dialog"}

          "/notifications" ->
            {"choose_notifications_delete_all", %{}, "cancel_notifications_delete_all",
             "notifications-delete-dialog"}

          "/notifications/84111" ->
            {"choose_notification_delete", %{}, "cancel_notification_delete",
             "notification-delete-dialog"}

          _ ->
            nil
        end

      if events do
        {choose, params, cancel, id} = events
        render_hook(view, choose, params)
        assert has_element?(view, "##{id}[open][aria-labelledby]")
        assert_native_controls(Dawarich.Test.NativeAdminUI.html(view))
        render_hook(view, cancel, %{})
        refute has_element?(view, "##{id}[open]")
      end

      if path == "/imports/84111" do
        assert has_element?(view, "#extraction-dialog-84111[aria-labelledby]")

        assert has_element?(
                 view,
                 ~s(#extraction-dialog-84111 form[phx-submit="extract_import"] input[type=submit][phx-disable-with])
               )
      end

      GenServer.stop(view.pid)
    end

    assert [[1]] = Repo.query!("SELECT count(*) FROM exports WHERE id=84111", [], log: false).rows

    assert [[1]] =
             Repo.query!("SELECT count(*) FROM notifications WHERE id=84111", [], log: false).rows
  end

  test "native family and sharing pages and open confirmations have accessible names without Hotwire" do
    saved = Map.new(~w(SELF_HOSTED DAWARICH_RAILS), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "true")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      for {key, value} <- saved,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    owner = FrameSeeds.seed_family!(FrameSeeds.load_family("owner_en"))
    manager = FrameSeeds.seed_management!("hub_active_shared_en")

    Repo.query!("UPDATE users SET active_until='3026-01-01' WHERE id=$1", [manager.id],
      log: false
    )

    Repo.query!("UPDATE family_location_requests SET expires_at='3026-01-01' WHERE status=0", [],
      log: false
    )

    FrameSeeds.track!(manager.id, 99701, %{
      start_at: ~N[2026-10-03 08:00:00],
      end_at: ~N[2026-10-03 09:00:00],
      dominant_mode: 1
    })

    FrameSeeds.stat!(manager.id, 2026, 10)

    Repo.query!(
      "INSERT INTO digests(user_id,year,period_type,created_at,updated_at) VALUES($1,2026,1,NOW(),NOW())",
      [manager.id],
      log: false
    )

    paths = [
      {owner.id, "/family"},
      {owner.id, "/family/edit"},
      {owner.id, "/family/invitations"},
      {90103, "/family/new"},
      {90102, "/family/location_requests/94001"},
      {manager.id, "/share_links/hub"},
      {manager.id, "/share_links/hub?tab=shared"},
      {manager.id, "/share_links/live/new"},
      {manager.id, "/share_links/timeline/new"},
      {manager.id, "/trips/99101/share_link/new"},
      {manager.id, "/tracks/99701/share_link/new"},
      {manager.id, "/stats/2026/10/sharing"},
      {manager.id, "/digests/2026/sharing"},
      {manager.id, "/achievements/country_fr/sharing"}
    ]

    routes =
      DawarichWeb.Router.__routes__()
      |> Enum.filter(fn
        %{metadata: %{phoenix_live_view: {_, _, _, %{name: name}}}} ->
          name in [:family_pages, :native_sharing]

        _ ->
          false
      end)

    assert length(routes) == 12

    assert %{phoenix_live_view: {DawarichWeb.FamiliesLive.NativeMap, _, _, _}} =
             Phoenix.Router.route_info(DawarichWeb.Router, "GET", "/family", "a")

    for locale <- ~w(en de), {id, path} <- paths do
      uri = path <> if(String.contains?(path, "?"), do: "&", else: "?") <> "locale=" <> locale
      conn = get(RailsUser.signed_in(id) |> RailsUser.connecting_as(id), uri)
      {:ok, view, connected} = live(conn)
      for html <- [html_response(conn, 200), connected], do: assert_native_controls(html)

      events =
        case path do
          "/family" ->
            assert has_element?(view, ~s([data-native-family-action=remove_member]))
            nil

          "/share_links/live/new" ->
            {"sharing_prepare", %{"action" => "revoke"}, "sharing_cancel", "sharing-confirm"}

          _ ->
            nil
        end

      if events do
        {prepare, attrs, cancel, dialog} = events
        render_hook(view, prepare, attrs)
        assert has_element?(view, "##{dialog}[data-pending=true]")
        html = Dawarich.Test.NativeAdminUI.html(view)
        assert_native_controls(html)

        named =
          html
          |> LazyHTML.from_document()
          |> LazyHTML.query("##{dialog}")
          |> LazyHTML.attribute("aria-labelledby")

        assert [title] = named

        assert html
               |> LazyHTML.from_document()
               |> LazyHTML.query("##{title}")
               |> LazyHTML.text()
               |> String.trim() != ""

        render_hook(view, cancel, %{})
        refute has_element?(view, "##{dialog}[data-pending=true]")
      end

      GenServer.stop(view.pid)
    end

    assert [[1]] =
             Repo.query!("SELECT count(*) FROM family_memberships WHERE id=92002", [], log: false).rows

    assert [[7]] =
             Repo.query!("SELECT count(*) FROM shared_links WHERE user_id=$1", [manager.id],
               log: false
             ).rows
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

  test "native Places and open form dialogs have unique accessible controls and no Hotwire", %{
    user: user
  } do
    mode = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if mode,
        do: System.put_env("DAWARICH_RAILS", mode),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    conn = RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id) |> get("/places")
    assert_native_controls(html_response(conn, 200))
    {:ok, view, connected} = live(conn)
    assert_native_controls(connected)
    FrameSeeds.place!(user.id, 84_112, "Native <literal>")
    render_patch(view, "/places?page=1")
    assert_native_controls(render(view))

    for {event, params} <- [
          {"open_create", %{}},
          {"open_edit", %{"id" => "84112"}},
          {"open_detail", %{"id" => "84112"}},
          {"request_delete", %{"id" => "84112"}}
        ] do
      render_click(view, event, params)
      assert_native_controls(render(view))
      render_click(view, "cancel_form", %{})
    end

    render_click(view, "open_create", %{})
    gen = Dawarich.Test.NativePlaces.generation(view, :form_state)

    render_submit(view, "save_place", %{
      "generation" => gen,
      "place" => %{"name" => "", "latitude" => "invalid", "longitude" => ""}
    })

    assert has_element?(view, "dialog[id^=place-form] [role=alert]")
    assert_native_controls(render(view))

    render_click(view, "validate_place", %{
      "generation" => gen,
      "place" => %{"name" => "Nearby", "latitude" => "0", "longitude" => "0"}
    })

    render_click(view, "nearby", %{"generation" => gen})
    assert_native_controls(render(view))
    render_async(view)
    assert_native_controls(render(view))
  end
end
