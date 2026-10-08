defmodule DawarichWeb.MapDataParityTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn
  import Dawarich.Test.RawHTTP
  alias Dawarich.Repo

  alias Dawarich.Test.{
    ApiGolden,
    FrameSeeds,
    MapStimulus,
    ParityHTML,
    RailsFormRequests,
    RailsUser
  }

  alias DawarichWeb.{Locale, MapFrames, PointsLive, TagsLive}
  @endpoint DawarichWeb.Endpoint
  @dir "test/fixtures/map_data"
  @points ~w(address_direct address_empty address_foreign address_full address_guest points_asc
    points_berlin_dst points_cloud_pro points_desc points_empty points_empty_import points_epoch
    points_geocoding_disabled points_guest points_import points_iso points_lite points_lite_dst
    points_lite_leap points_march_default points_mi points_named_start points_named_end
    points_page1 points_page2 points_page_out points_pre_epoch_import points_pre_epoch_explicit)
  @tags ~w(tags_edit tags_edit_blank tags_edit_guest tags_foreign_edit tags_new tags_new_guest)
  @segments ~w(segments_corrected segments_disabled_mi segments_empty segments_enabled
    segments_foreign segments_gap_239 segments_gap_240 segments_guest segments_isolated_short
    segments_legacy_durations segments_long_leg segments_ordinary segments_stationary
    segments_transfer segments_uncertain segments_zero_ribbon)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    old = Map.new(~w(TIME_ZONE SELF_HOSTED JWT_SECRET_KEY MANAGER_URL), &{&1, System.get_env(&1)})
    System.put_env("JWT_SECRET_KEY", "a6s3-synthetic-jwt-not-for-production")

    on_exit(fn ->
      for {key, value} <- old,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)
  end

  test "all declared map-data oracle cases are present" do
    expected =
      for name <- @points ++ @tags ++ @segments, suffix <- [".json", ".html"], do: name <> suffix

    expected = expected ++ ~w(address_empty.target.html address_full.target.html)
    assert @dir |> File.ls!() |> Enum.sort() == Enum.sort(expected)
  end

  test "point page corpus and address targets match Rails" do
    for name <- @points, do: compare(name)
  end

  test "tag page corpus preserves form fields and Stimulus attributes" do
    for name <- @tags, do: compare(name)
  end

  test "segment corpus preserves forms condensed legs and Stimulus attributes" do
    for name <- @segments, do: compare(name)
  end

  defp compare(name) do
    Dawarich.FixtureCleanup.delete!(
      Repo,
      ~w(public.users  public.imports  public.points  public.places  public.areas  public.tags  public.taggings  public.visits  public.place_visits  public.tracks  public.track_segments  public.stats  public.instance_settings)
    )

    state = File.read!("#{@dir}/#{name}.json") |> Jason.decode!()

    if state["env"]["TIME_ZONE"],
      do: System.put_env("TIME_ZONE", state["env"]["TIME_ZONE"]),
      else: System.delete_env("TIME_ZONE")

    System.put_env("SELF_HOSTED", to_string(state["self_hosted"]))
    System.put_env("MANAGER_URL", "https://manager.a6s3-fixture.test")
    if state["foreign"], do: seed(state["foreign"])
    user = seed(state)

    if state["geocoding"] do
      stamp = ~N[2026-10-03 10:00:00]

      Repo.insert_all("instance_settings", [
        %{
          key: "photon_api_host",
          value: "photon.example.invalid",
          created_at: stamp,
          updated_at: stamp
        }
      ])
    end

    rails = File.read!("#{@dir}/#{name}.html")
    {:ok, now, 0} = DateTime.from_iso8601(state["now"])
    %URI{path: path, query: query} = URI.parse(state["path"])
    params = URI.decode_query(query || "")
    locale = Locale.resolve(nil, user, %{})

    ctx = %{
      user: user,
      locale: locale,
      now: now,
      self_hosted: state["self_hosted"],
      csrf: "CSRF",
      csrf_changes: %{},
      query: params
    }

    fallback =
      (state["status"] == 404 and state["kind"] == "segments") or
        name in ~w(points_named_start points_named_end points_pre_epoch_import)

    if state["status"] == 200 and not fallback and name != "address_direct" do
      native = body(state, ctx, path)

      expected =
        if state["kind"] == "point_address",
          do: File.read!("#{@dir}/#{name}.target.html"),
          else: rails

      if state["kind"] == "points", do: assert_checkbox_ids(native, expected, name)
      native = point_checkbox_projection(native)

      assert projected(native) == ParityHTML.normalize(expected),
             "#{name}: " <>
               ParityHTML.first_difference(
                 projected(native),
                 ParityHTML.normalize(expected)
               )

      assert stimulus(native) == stimulus(expected), "#{name}: Stimulus attributes differ"

      assert ParityHTML.stimulus(native, "[data-testid]") ==
               ParityHTML.stimulus(expected, "[data-testid]"),
             "#{name}: test IDs differ"
    end

    endpoint(state, user, rails, name, fallback)
  end

  defp seed(%{"user" => nil}), do: nil

  defp seed(state) do
    user = FrameSeeds.seed!(Map.put(state, "rows", Map.drop(state["rows"], ["points"])))
    for row <- Map.get(state["rows"], "imports", []), do: ApiGolden.insert!("imports", row)
    for row <- Map.get(state["rows"], "points", []), do: ApiGolden.insert!("points", row)
    user
  end

  defp body(%{"kind" => "points"}, ctx, _path) do
    {:ok, result} =
      Dawarich.PointList.load(ctx.user, ctx.query, ctx.now, self_hosted: ctx.self_hosted)

    summary =
      DawarichWeb.PointListFormat.entries(
        ctx.locale,
        result.count,
        result.page,
        length(result.rows),
        result.total_pages
      )

    assigns =
      Map.merge(result, %{
        locale: ctx.locale,
        query: ctx.query,
        summary: summary,
        unit: get_in(ctx.user.settings, ["maps", "distance_unit"]) || "km",
        rails_csrf_token: "CSRF"
      })

    render_component(&PointsLive.Index.render/1, assigns)
  end

  defp body(%{"kind" => "tags"}, ctx, _path),
    do:
      render_component(&TagsLive.Index.render/1,
        locale: ctx.locale,
        tags: Dawarich.TagPages.index(ctx.user),
        rails_csrf_token: "CSRF"
      )

  defp body(%{"kind" => "tag_form"} = state, ctx, path) do
    kind = if path == "/tags/new", do: "new", else: "edit"

    tag =
      if kind == "new",
        do: %{id: nil, name: nil, icon: nil, color: nil, privacy_radius_meters: nil},
        else:
          elem(
            Dawarich.TagPages.edit(
              ctx.user,
              path |> String.split("/") |> Enum.at(2) |> String.to_integer()
            ),
            1
          )

    render_component(&TagsLive.Form.render/1,
      locale: ctx.locale,
      tag: tag,
      kind: kind,
      tag_title: DawarichWeb.Translate.t(ctx.locale, "tags.#{kind}.#{kind}_tag", %{}),
      rails_csrf_token: "CSRF",
      default_emoji: state["default_icon"]
    )
  end

  defp body(%{"kind" => kind}, ctx, path) do
    %{plug_opts: action, path_params: params} =
      Phoenix.Router.route_info(DawarichWeb.Router, "GET", path, "www.example.com")

    ctx = Map.merge(ctx, %{id: params["id"], track_id: params["track_id"]})
    assert action == if(kind == "segments", do: :segments, else: :address)
    action = if action == :address, do: :point_address, else: action
    assert {:ok, "text/html", html} = MapFrames.body(action, ctx)
    IO.iodata_to_binary(html)
  end

  defp endpoint(state, user, rails, name, fallback) do
    conn = if user, do: RailsUser.signed_in(user.id), else: build_conn()
    conn = put_req_header(conn, "accept", state["accept"])

    conn =
      if state["turbo_frame"],
        do: put_req_header(conn, "turbo-frame", state["turbo_frame"]),
        else: conn

    conn =
      cond do
        fallback ->
          replay(conn, state, rails)

        state["status"] == 404 and state["kind"] == "tag_form" ->
          {404, headers, body} = assert_error_sent(404, fn -> get(conn, state["path"]) end)
          %{conn | status: 404, resp_headers: headers, resp_body: body, state: :sent}

        true ->
          get(conn, state["path"])
      end

    assert conn.status == state["status"], name

    if name == "address_direct" do
      frame = fn body ->
        body
        |> LazyHTML.from_document()
        |> LazyHTML.query("turbo-frame")
        |> LazyHTML.to_html()
        |> ParityHTML.normalize()
      end

      assert frame.(conn.resp_body) == frame.(rails), name
      assert conn.resp_body =~ "<!DOCTYPE html>"
    end

    assert conn |> get_resp_header("content-type") |> hd() |> String.split(";") |> hd() ==
             state["content_type"],
           name

    assert get_resp_header(conn, "vary") == List.wrap(state["vary"]), name

    if state["location"],
      do: assert(get_resp_header(conn, "location") == [state["location"]], name)

    if state["status"] == 302 do
      session = RailsFormRequests.rails_session(conn)

      assert %{
               "user_return_to" => session["user_return_to"],
               "alert" => get_in(session, ["flash", "flashes", "alert"])
             } == state["session"],
             name
    else
      refute conn.private[:dawarich_rails_session_changes], name

      if state["status"] == 200 and not fallback and
           state["kind"] in ["points", "tags", "tag_form"] do
        title =
          Map.fetch!(state, "title")
          |> Phoenix.HTML.html_escape()
          |> Phoenix.HTML.safe_to_string()

        assert conn.resp_body =~ ">#{title}</title>", name
      end
    end
  end

  defp replay(conn, state, rails) do
    upstream = RailsFormRequests.upstream!()

    task =
      Task.async(fn ->
        socket = accept(upstream)
        {head, _} = read_head(socket)
        assert request_line(head) == "GET #{state["path"]} HTTP/1.1"
        vary = if state["vary"], do: "Vary: #{state["vary"]}\r\n", else: ""

        reply(
          socket,
          "HTTP/1.1 #{state["status"]} Rails\r\nContent-Type: text/html; charset=utf-8\r\n#{vary}Content-Length: #{byte_size(rails)}\r\n\r\n#{rails}"
        )
      end)

    result = get(conn, state["path"])
    Task.await(task)
    assert result.resp_body == rails
    result
  end

  defp stimulus(html),
    do:
      MapStimulus.attributes("<html><body>#{html}</body></html>", ["body"])
      |> Enum.filter(&match?({"body", _, _}, &1))

  defp assert_checkbox_ids(native, rails, name) do
    query = fn html, attr ->
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("input[name='point_ids[]']")
      |> LazyHTML.attribute(attr)
    end

    assert query.(rails, "id") == List.duplicate("point_ids_", length(query.(rails, "value"))),
           name

    assert query.(native, "id") == Enum.map(query.(rails, "value"), &"point_ids_#{&1}"), name
    assert query.(native, "value") == query.(rails, "value"), name
  end

  defp projected(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.to_tree()
    |> tag_island()
    |> ParityHTML.normalize()
  end

  defp tag_island(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &tag_island/1)

  defp tag_island({"fieldset", attrs, children}) do
    assert Enum.sort(attrs) ==
             Enum.sort([{"disabled", ""}, {"data-rails-form-ready", ""}, {"class", "contents"}])

    tag_island(children)
  end

  defp tag_island({"div", attrs, children} = node) do
    case Map.new(attrs) do
      %{"id" => "tag-fields-" <> id, "phx-hook" => "RailsStimulus", "phx-update" => "ignore"} ->
        assert id == "new" or id =~ ~r/\A\d+\z/

        assert Enum.sort(attrs) ==
                 Enum.sort([
                   {"id", "tag-fields-" <> id},
                   {"phx-hook", "RailsStimulus"},
                   {"phx-update", "ignore"},
                   {"inert", ""}
                 ])

        tag_island(children)

      %{"id" => "points-page-" <> key, "phx-hook" => "RailsStimulus"} ->
        assert {:ok, _query} = Base.url_decode64(key, padding: false)

        assert Enum.sort(attrs) ==
                 Enum.sort([
                   {"id", "points-page-" <> key},
                   {"data-controller", "checkbox-select-all"},
                   {"phx-hook", "RailsStimulus"},
                   {"phx-update", "ignore"},
                   {"inert", ""}
                 ])

        tag_island(children)

      _ ->
        [{elem(node, 0), attrs, tag_island(children)}]
    end
  end

  defp tag_island({tag, attrs, children}), do: [{tag, attrs, tag_island(children)}]
  defp tag_island(node), do: [node]

  defp point_checkbox_projection(html),
    do: String.replace(html, ~r/(name="point_ids\[\]" id=")point_ids_\d+(")/, "\\1point_ids_\\2")
end
