defmodule DawarichWeb.PointsLiveTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Dawarich.Test.FormIsolation
  import Plug.Conn

  alias Dawarich.{RailsCookies, RailsSecret, Repo}
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  alias DawarichWeb.{HumanDatetime, MapDataGate, PointListFormat, Router}

  @endpoint DawarichWeb.Endpoint
  @range "start_at=1772359200&end_at=1772445600"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    %{user: FrameSeeds.user!(8371, %{"timezone" => "UTC", "maps" => %{"distance_unit" => "km"}})}
  end

  defp live_as(user, path) do
    assert %{plug: Phoenix.LiveView.Plug} =
             Phoenix.Router.route_info(Router, "GET", "/points", "localhost")

    live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)
  end

  defp fill(user, n) do
    for i <- 1..n, do: FrameSeeds.point!(user.id, 837_100 + i, 1_772_359_200 + (i - 1) * 60)
  end

  defp attr(html, selector, name),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  @tag :standalone_search
  test "standalone Rails search form retains filters pagination user scope and signed bulk deletion",
       %{user: user} do
    previous = Map.take(System.get_env(), ~w(DAWARICH_RAILS SELF_HOSTED))
    System.put_env(%{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true"})

    on_exit(fn ->
      for key <- ~w(DAWARICH_RAILS SELF_HOSTED) do
        if previous[key], do: System.put_env(key, previous[key]), else: System.delete_env(key)
      end
    end)

    fill(user, 51)
    foreign = FrameSeeds.user!(8372, %{"timezone" => "UTC"})
    FrameSeeds.point!(foreign.id, 837_201, 1_772_359_200)
    FrameSeeds.point!(user.id, 837_202, 1_600_000_000)
    stamp = ~N[2026-03-01 10:00:00]

    Repo.insert_all("imports", [
      %{id: 83711, user_id: user.id, name: "Synthetic.json", created_at: stamp, updated_at: stamp}
    ])

    Repo.query!("UPDATE points SET import_id=83711 WHERE id=837101")

    query =
      "start_at=2026-03-01T10%3A00&end_at=2026-03-02T10%3A00&import_id=&commit=Search&order_by=asc"

    session = Dawarich.Test.RailsUser.session(user.id)

    conn =
      RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id) |> get("/points?" <> query)

    assert conn.status == 200
    {:ok, view, html} = live(conn)

    assert attr(html, "#points input[name='point_ids[]']", "value") ==
             Enum.map(837_101..837_150, &to_string/1)

    refute html =~ "point_837201"
    refute html =~ "point_837202"
    assert attr(html, "#bulk_destroy_form input[name='authenticity_token']", "value") != []
    assert attr(html, "#bulk_destroy_form input[name='_method']", "value") == ["delete"]
    assert attr(html, "input[name='start_at']", "value") == ["2026-03-01T10:00"]
    assert attr(html, "select[name='import_id'] option", "value") == ["", "83711"]

    html =
      view |> element(".flex.justify-center.mb-4 [aria-label='pager'] a", "2") |> render_click()

    assert attr(html, "#points input[name='point_ids[]']", "value") == ["837151"]

    assert_patch(
      view,
      "/points?end_at=2026-03-02T10%3A00&import_id=&order_by=asc&page=2&start_at=2026-03-01T10%3A00"
    )

    {:ok, _, filtered} =
      live_as(user, "/points?" <> String.replace(query, "import_id=", "import_id=83711"))

    assert attr(filtered, "#points input[name='point_ids[]']", "value") == ["837101"]

    path = "/points/bulk_destroy?" <> query
    unsigned = post_bulk(session, path, "_method=delete&point_ids[]=837101")
    assert unsigned.status == 422

    signed =
      "_method=delete&point_ids[]=837101&point_ids[]=837201&authenticity_token=" <>
        URI.encode_www_form(DawarichWeb.RailsCsrf.masked_token(session))

    deleted = post_bulk(session, path, signed)
    assert deleted.status == 303

    assert URI.decode_query(URI.parse(hd(get_resp_header(deleted, "location"))).query) == %{
             "start_at" => "2026-03-01T10:00",
             "end_at" => "2026-03-02T10:00",
             "import_id" => "",
             "order_by" => "asc"
           }

    assert Repo.query!("SELECT id FROM points WHERE id IN (837101,837201) ORDER BY id").rows == [
             [837_201]
           ]
  end

  defp post_bulk(session, path, body) do
    build_conn()
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", to_string(byte_size(body)))
    |> put_req_header("accept", "text/html")
    |> post(path, body)
  end

  test "coordinates velocity and seconds match Rails table formatting" do
    assert PointListFormat.coordinates(%{lat: 51.339700123456, lon: 12.373468123456}) ==
             "51.339700, 12.373468"

    assert PointListFormat.velocity(1.234, "km") == "4.4"
    assert PointListFormat.velocity(1.234, "mi") == "2.8"
    assert PointListFormat.velocity(nil, "km") == ""
    assert PointListFormat.velocity(0.0, "km") == "0.0"
    assert PointListFormat.velocity(-1.5, "km") == "-1.5"
    assert PointListFormat.speed_class(-0.5) == "text-default"
    assert PointListFormat.speed_class(-1.5) == "text-red-500"
    at = %{local: ~N[2026-03-01 10:00:27], offset: 0, utc: true}
    html = render_component(&HumanDatetime.human_datetime_with_seconds/1, locale: "en", at: at)
    assert html =~ "1 Mar 2026, 10:00:27"
    assert html =~ ~s(data-tip="2026-03-01T10:00:27Z")

    refute render_component(&HumanDatetime.human_datetime/1, locale: "en", at: at) =~
             "10:00:27</span>"
  end

  test "list controls preserve original filter and bulk form names", %{user: user} do
    stamp = ~N[2026-03-01 10:00:00]

    Repo.insert_all("imports", [
      %{id: 83711, user_id: user.id, name: "Synthetic.json", created_at: stamp, updated_at: stamp}
    ])

    fill(user, 1)
    Repo.query!("UPDATE points SET import_id = 83711 WHERE user_id = $1", [user.id])
    {:ok, _view, html} = live_as(user, "/points?#{@range}&import_id=83711&order_by=asc")
    [action] = attr(html, "#bulk_destroy_form", "action")
    assert URI.parse(action).path == "/points/bulk_destroy"

    assert URI.decode_query(URI.parse(action).query) == %{
             "action" => "index",
             "controller" => "points",
             "start_at" => "1772359200",
             "end_at" => "1772445600",
             "import_id" => "83711",
             "order_by" => "asc"
           }

    assert attr(html, "#bulk_destroy_form input[name='_method']", "value") == ["delete"]
    assert attr(html, "input[name='point_ids[]']", "value") == ["837101"]
    assert attr(html, "input[name='start_at']", "value") == ["2026-03-01T10:00"]
    assert attr(html, "select[name='import_id'] option[selected]", "value") == ["83711"]

    assert attr(html, "#points [data-controller='checkbox-select-all']", "phx-hook") == [
             "RailsStimulus"
           ]

    assert attr(html, "#bulk_destroy_form", "phx-submit") == []
    assert html =~ "Synthetic.json"
  end

  test "selection island survives hydration and is replaced for a different page", %{user: user} do
    fill(user, 51)

    conn =
      get(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), "/points?#{@range}")

    [static_id] = attr(conn.resp_body, "[id^='points-page-']", "id")
    assert_form_isolated(conn.resp_body, "#bulk_destroy_form")
    {:ok, view, html} = live(conn)
    assert_form_isolated(html, "#bulk_destroy_form")
    assert attr(html, "[id^='points-page-']", "id") == [static_id]
    assert attr(html, "#points [phx-hook='RailsStimulus']", "phx-update") == ["ignore"]
    assert attr(html, "#points input[name='point_ids[]']", "value") |> length() == 50

    html =
      view |> element(".flex.justify-center.mb-4 [aria-label='pager'] a", "2") |> render_click()

    [next_id] = attr(html, "[id^='points-page-']", "id")
    assert_form_isolated(html, "#bulk_destroy_form")
    refute next_id == static_id
    assert attr(html, "#points input[name='point_ids[]']", "value") == ["837101"]
  end

  test "pagination and order navigation render the selected page", %{user: user} do
    fill(user, 51)
    {:ok, view, html} = live_as(user, "/points?#{@range}&order_by=asc")
    assert attr(html, "#points tbody tr", "id") == Enum.map(837_101..837_150, &"point_#{&1}")

    html =
      view |> element(".flex.justify-center.mb-4 [aria-label='pager'] a", "2") |> render_click()

    assert_patch(view, "/points?end_at=1772445600&order_by=asc&page=2&start_at=1772359200")
    assert attr(html, "#points tbody tr", "id") == ["point_837151"]
    assert html =~ "51"
    {:ok, _desc, html} = live_as(user, "/points?#{@range}&order_by=desc")
    assert hd(attr(html, "#points tbody tr", "id")) == "point_837151"
    assert Enum.any?(attr(html, "thead a", "href"), &String.contains?(&1, "order_by=asc"))
  end

  test "geocoding disables the column and list fallback differs from address frame", %{user: user} do
    fill(user, 1)

    Repo.query!(
      "UPDATE points SET city = 'Fallback', country_name = 'Germany', geodata = '{}'::jsonb WHERE user_id = $1",
      [user.id]
    )

    {:ok, _view, disabled} = live_as(user, "/points?#{@range}")
    refute disabled =~ ">Address</th>"
    stamp = ~N[2026-03-01 10:00:00]

    Repo.insert_all("instance_settings", [
      %{
        key: "photon_api_host",
        value: "photon.example.invalid",
        created_at: stamp,
        updated_at: stamp
      }
    ])

    {:ok, _view, enabled} = live_as(user, "/points?#{@range}")
    assert enabled =~ "Fallback, Germany"

    assert PointListFormat.address(%{geodata: %{}, city: "Fallback", country_name: "Germany"}) ==
             "Fallback, Germany"

    assert PointListFormat.address(
             %{geodata: %{}, city: "Fallback", country_name: "Germany"},
             false
           ) == ""
  end

  test "points route and query writers hand back before page pipeline", %{user: user} do
    assert %{pipe_through: [:browser, :rails_user], rails_gate: {MapDataGate, :points?}} =
             Phoenix.Router.route_info(Router, "GET", "/points", "localhost")

    assert MapDataGate.points?(
             RailsUser.signed_in(user.id) |> Map.put(:query_string, @range),
             %{}
           )

    for query <- [
          "locale=de",
          "client=x",
          "aff=x",
          "via=x",
          "start_at[]=x",
          "page[]=2",
          "order_by=bad"
        ] do
      refute MapDataGate.points?(
               RailsUser.signed_in(user.id) |> Map.put(:query_string, query),
               %{}
             )
    end

    refute MapDataGate.points?(
             RailsUser.signed_in(user.id) |> put_req_header("x-dawarich-client", "test"),
             %{}
           )

    refute DawarichWeb.Strangler.page_request?(
             build_conn()
             |> Map.put(:path_info, ["points"])
             |> put_req_header("x-requested-with", "XMLHttpRequest")
           )
  end

  test "named dates and unproved timestamps hand back before the browser pipeline", %{user: user} do
    for {name, key} <- [{"points_named_start", "start_at"}, {"points_named_end", "end_at"}] do
      state = File.read!("test/fixtures/map_data/#{name}.json") |> Jason.decode!()
      html = File.read!("test/fixtures/map_data/#{name}.html")
      assert attr(html, "input[name='#{key}']", "value") == ["2026-03-01T00:00"]

      refute MapDataGate.points?(
               RailsUser.signed_in(user.id)
               |> Map.put(:query_string, URI.parse(state["path"]).query),
               %{}
             )
    end

    for key <- ["start_at", "end_at"],
        value <- [
          "Mar 2026",
          "yesterday",
          "2026-02-30T10:00:00Z",
          "2026-03-01T10:00:00+99:99",
          "2026-03-01T10:00:00+05",
          "2026-03-01T10:00:00+0500"
        ] do
      refute MapDataGate.points?(
               RailsUser.signed_in(user.id)
               |> Map.put(:query_string, URI.encode_query(%{key => value})),
               %{}
             )
    end

    for key <- ["start_at", "end_at"],
        value <- [
          "",
          " ",
          "1772359200",
          "2026-03-01",
          "2026-03-01T10:00",
          "2026-03-01T10:00:00Z",
          "2026-03-01T10:00:00+05:00"
        ] do
      assert Dawarich.PointList.valid_params?(%{key => value})
    end
  end

  test "unclamped pre-epoch import defaults hand back and explicit bounds remain clamped", %{
    user: user
  } do
    omitted = File.read!("test/fixtures/map_data/points_pre_epoch_import.html")
    assert attr(omitted, "input[name='start_at']", "value") == ["1969-12-31T00:00"]
    assert attr(omitted, "input[name='end_at']", "value") == ["1969-12-31T23:59"]
    assert attr(omitted, "#points tbody tr", "id") == ["point_830801"]
    explicit = File.read!("test/fixtures/map_data/points_pre_epoch_explicit.html")
    assert attr(explicit, "input[name='start_at']", "value") == ["1970-01-01T00:00"]
    assert attr(explicit, "input[name='end_at']", "value") == ["1970-01-01T00:00"]
    assert attr(explicit, "#points tbody tr", "id") == []
    stamp = ~N[2026-03-01 10:00:00]

    Repo.insert_all("imports", [
      %{id: 83712, user_id: user.id, name: "Historic.json", created_at: stamp, updated_at: stamp}
    ])

    FrameSeeds.point!(user.id, 837_201, DateTime.to_unix(~U[1969-12-31 10:00:00Z]))
    Repo.query!("UPDATE points SET import_id = 83712 WHERE id = 837201")

    for bounds <- [
          %{},
          %{"start_at" => "1969-12-31T00:00:00Z"},
          %{"end_at" => "1970-01-02T00:00:00Z"}
        ] do
      refute MapDataGate.points?(
               RailsUser.signed_in(user.id)
               |> Map.put(:query_string, URI.encode_query(Map.put(bounds, "import_id", "83712"))),
               %{}
             )
    end

    params = %{
      "import_id" => "83712",
      "start_at" => "1969-12-31T00:00:00Z",
      "end_at" => "1969-12-31T23:59:59Z"
    }

    assert {:ok, page} =
             Dawarich.PointList.load(user, params, ~U[2026-03-31 10:00:00Z], self_hosted: true)

    assert {page.window.start, page.window.end, page.rows} ==
             {"1970-01-01T00:00:00Z", "1970-01-01T00:00:00Z", []}
  end

  test "signed out list records Rails return URL and alert" do
    assert %{plug: Phoenix.LiveView.Plug} =
             Phoenix.Router.route_info(Router, "GET", "/points", "localhost")

    conn = get(build_conn(), "/points?#{@range}")
    assert redirected_to(conn, 302) == "http://www.example.com/users/sign_in"

    {:ok, session} =
      RailsCookies.decrypt(
        conn.resp_cookies["_dawarich_session"].value,
        "_dawarich_session",
        RailsSecret.fetch(),
        DateTime.utc_now()
      )

    assert session["user_return_to"] == "/points?#{@range}"

    assert session["flash"]["flashes"]["alert"] ==
             "You need to sign in or sign up before continuing."
  end
end
