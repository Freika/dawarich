defmodule DawarichWeb.SharingParityTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [get_resp_header: 2, put_req_header: 3]

  alias Dawarich.Test.SharingSeeds

  @endpoint DawarichWeb.Endpoint
  @external_resource "test/fixtures/sharing/pages.json"
  @pages SharingSeeds.fixture("pages.json")["pages"]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    SharingSeeds.load!()
    :ok
  end

  defp request(%{"verb" => "get", "path" => path}, cookie), do: get(conn(cookie), path)

  defp request(%{"verb" => "post", "path" => path, "params" => params}, cookie) do
    body = URI.encode_query(params || %{})

    conn(cookie)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> post(path, body)
  end

  defp conn(nil), do: build_conn()
  defp conn({name, value}), do: build_conn() |> put_req_header("cookie", "#{name}=#{value}")

  defp unlocked(%{"cookie" => nil}), do: nil

  defp unlocked(%{"cookie" => name, "path" => path}) do
    unlock =
      Enum.find(@pages, &(&1["path"] == path <> "/unlock" and &1["status"] == 302))

    response = request(unlock, nil)
    {name, response |> cookie_lines() |> Map.fetch!(name) |> elem(0)}
  end

  defp cookie_lines(conn) do
    for {"set-cookie", line} <- conn.resp_headers, into: %{} do
      [pair | attributes] = line |> String.split(";") |> Enum.map(&String.trim/1)
      [name, value] = String.split(pair, "=", parts: 2)

      attributes =
        attributes
        |> Enum.map(&(&1 |> String.downcase() |> String.replace(~r/\Aexpires=.*/, "expires")))
        |> Enum.sort()

      {name, {value, attributes}}
    end
  end

  defp header(conn, name), do: conn |> get_resp_header(name) |> Enum.join(", ")

  defp text(doc, selector),
    do:
      doc
      |> LazyHTML.query(selector)
      |> LazyHTML.text()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

  defp unmask(value) do
    <<pad::binary-size(32), masked::binary-size(32)>> = Base.url_decode64!(value, padding: false)
    pad |> :crypto.exor(masked) |> Base.encode16(case: :lower)
  end

  test "native public unlock form and csrf meta preserve Rails session token derivation" do
    csrf = SharingSeeds.fixture("csrf.json")
    id = csrf["action"] |> String.split("/") |> Enum.at(2)
    cookie = Dawarich.Test.RailsUser.cookie(%{"_csrf_token" => csrf["session"]})
    html = conn({"_dawarich_session", cookie}) |> get("/s/#{id}") |> html_response(401)
    doc = LazyHTML.from_document(html)

    assert doc
           |> LazyHTML.query(~s(input[name="authenticity_token"]))
           |> LazyHTML.attribute("value")
           |> Enum.map(&unmask/1) ==
             [csrf["form"]]

    assert doc
           |> LazyHTML.query(~s(meta[name="csrf-token"]))
           |> LazyHTML.attribute("content")
           |> Enum.map(&unmask/1) ==
             [csrf["meta"]]
  end

  @resources File.read!("test/fixtures/sharing/resources.json") |> Jason.decode!()
  for entry <- @resources do
    @entry entry
    test "static resource #{@entry["name"]} matches Rails 1.16.0" do
      alias Dawarich.Test.{TripsSeeds, FrameSeeds, ParityHTML}

      TripsSeeds.trip!(%{
        id: 990_101,
        user_id: 9901,
        name: "Public fixture trip",
        distance: 4000,
        visited_countries: [],
        started_at: ~N[2026-05-10 08:00:00],
        ended_at: ~N[2026-05-11 09:00:00]
      })

      Dawarich.Repo.query!(
        "INSERT INTO action_text_rich_texts(record_type,record_id,name,body,created_at,updated_at) VALUES('Trip',990101,'description','<p>Public fixture notes</p>',NOW(),NOW())",
        [],
        log: false
      )

      Dawarich.Repo.insert_all("notes", [
        %{
          user_id: 9901,
          attachable_type: "Trip",
          attachable_id: 990_101,
          noted_at: ~N[2026-05-10 12:00:00],
          body: "Public day note",
          created_at: ~N[2026-05-10 12:00:00],
          updated_at: ~N[2026-05-10 12:00:00]
        }
      ])

      FrameSeeds.track!(9901, 990_102, %{
        start_at: ~N[2026-05-10 08:00:00],
        end_at: ~N[2026-05-10 09:00:00],
        distance: 1500,
        duration: 3600,
        avg_speed: 1.5,
        dominant_mode: 2,
        elevation_gain: 10,
        elevation_loss: 4
      })

      TripsSeeds.shared_link!(%{
        id: @entry["id"],
        user_id: 9901,
        resource_type: if(@entry["type"] == "trip", do: 0, else: 1),
        trip_id: if(@entry["type"] == "trip", do: 990_101, else: 990_102)
      })

      Dawarich.Repo.query!(
        "UPDATE shared_links SET name=$2,settings=$3 WHERE id=$1::text::uuid",
        [@entry["id"], "Public fixture share", @entry["settings"]],
        log: false
      )

      html =
        get(build_conn(), "/s/#{@entry["id"]}?locale=#{@entry["locale"]}") |> html_response(200)

      if dir = System.get_env("PARITY_DUMP") do
        File.mkdir_p!(dir)
        File.write!(Path.join(dir, @entry["name"] <> ".phoenix.html"), html)
      end

      actual = static_dom(html, "main")
      source = SharingSeeds.page(@entry["name"] <> ".html")

      source =
        if @entry["type"] == "track" and @entry["settings"]["show_stats"] == false do
          assert html |> LazyHTML.from_document() |> LazyHTML.query("main h1") |> LazyHTML.text() |> String.trim() ==
                   "Public fixture share"

          assert source =~ " · "
          Regex.replace(~r/(<h1[^>]*>).*?(<\/h1>)/s, source, "\\1Public fixture share\\2")
        else
          source
        end

      expected = static_dom("<main>" <> source <> "</main>", "main")

      assert actual == expected, ParityHTML.first_difference(actual, expected)
    end
  end

  for page <- @pages,
      page["verb"] == "get",
      String.starts_with?(page["name"], ["live_", "timeline_", "expired_", "revoked_", "unknown_"]) do
    @shell page
    test "public shell #{@shell["name"]} matches Rails 1.16.0" do
      conn = request(@shell, unlocked(@shell))

      actual =
        conn.resp_body
        |> String.replace(~s(id="native-public-map"), ~s(id="native-canonical-public-map"))

      source =
        SharingSeeds.page("#{@shell["name"]}.html")
        |> String.replace(~s(id="shared-live-map"), ~s(id="native-canonical-public-map"))
        |> String.replace(~s(id="shared-trip-map"), ~s(id="native-canonical-public-map"))

      actual = Dawarich.Test.ParityHTML.fragment(actual, "main")
      expected = Dawarich.Test.ParityHTML.fragment(source, "main")
      assert actual == expected, Dawarich.Test.ParityHTML.first_difference(actual, expected)
    end
  end

  for page <- @pages do
    @page page

    name =
      if page["verb"] == "get",
        do:
          "#{page["name"]} preserves source sharing behavior through its declared native envelope",
        else: "#{page["name"]} answers as Rails does"

    test name do
      id = @page["path"] |> String.split("/") |> Enum.at(2) |> String.split("?") |> hd()
      cookie = unlocked(@page)
      before = @page["touched"] && SharingSeeds.view_count(id)
      conn = request(@page, cookie)

      native = @page["verb"] == "get"

      expected_status =
        if native && String.starts_with?(@page["name"], "missing_"),
          do: 404,
          else: @page["status"]

      assert conn.status == expected_status

      for {name, value} <- @page["headers"] do
        expected = if native && name == "cache-control", do: "private, no-store", else: value
        assert header(conn, name) == expected, name
      end

      assert header(conn, "etag") != "" == (!native && @page["etag"])

      assert Map.new(Map.delete(cookie_lines(conn), "_dawarich_phoenix"), fn {name,
                                                                              {_value, attrs}} ->
               {name, attrs}
             end) == @page["set_cookies"]

      if @page["touched"], do: assert(SharingSeeds.view_count(id) - before == @page["touched"])

      if @page["title"] do
        html = conn.resp_body
        rails = SharingSeeds.page("#{@page["name"]}.html")
        doc = LazyHTML.from_document(html)
        available = @page["status"] == 200 && !String.starts_with?(@page["name"], "missing_")

        title =
          if available,
            do: DawarichWeb.Layouts.page_title(@page["html_lang"], @page["title"]),
            else:
              if(native,
                do: DawarichWeb.Layouts.page_title(@page["html_lang"], nil),
                else: @page["title"]
              )

        assert doc |> LazyHTML.query("title") |> LazyHTML.text() == title

        assert LazyHTML.query(doc, "script[type=importmap], [data-controller], turbo-frame")
               |> Enum.empty?()

        assert html =~ "/native/app"

        if native do
          assert Map.has_key?(cookie_lines(conn), "_dawarich_phoenix")
          {_value, attrs} = cookie_lines(conn)["_dawarich_phoenix"]
          assert attrs == ["httponly", "path=/", "samesite=lax"]

          assert doc |> LazyHTML.query("html") |> LazyHTML.attribute("lang") == [
                   @page["html_lang"]
                 ]

          if available do
            assert LazyHTML.query(doc, "#native-public-map[phx-hook=PublicMap]") |> Enum.count() ==
                     1

            config =
              doc
              |> LazyHTML.query("#native-public-map")
              |> LazyHTML.attribute("data-map-config")
              |> hd()
              |> Jason.decode!()

            link = Enum.find(SharingSeeds.fixture("seed.json")["shared_links"], &(&1["id"] == id))

            assert text(doc, "main h1") ==
                     if(link["resource_type"] == 2,
                       do: text(LazyHTML.from_fragment(rails), "main h1"),
                       else: link["name"]
                     )

            assert config["shareId"] == id

            route =
              if link["resource_type"] == 3,
                do:
                  link["settings"]["show_route"] not in [
                    nil,
                    false,
                    "",
                    "0",
                    "false",
                    "FALSE",
                    "f",
                    "F",
                    "off",
                    "OFF"
                  ],
                else: true

            assert config["routeEnabled"] == route
            assert config["photosEnabled"] == (link["settings"]["show_photos"] == true)

            if link["resource_type"] == 2 do
              assert config["publicType"] == "timeline"

              assert Date.from_iso8601!(String.slice(config["range"]["startAt"], 0, 10)) ==
                       Date.from_iso8601!(link["settings"]["start_date"])

              assert Date.from_iso8601!(String.slice(config["range"]["endAt"], 0, 10)) ==
                       Date.from_iso8601!(link["settings"]["end_date"])
            end
          else
            if @page["status"] in [401, 404] do
              actual = Dawarich.Test.ParityHTML.fragment(html, "main")
              expected = Dawarich.Test.ParityHTML.fragment(rails, "main")

              assert actual == expected,
                     Dawarich.Test.ParityHTML.first_difference(actual, expected)
            end

            assert Enum.empty?(LazyHTML.query(doc, "#native-public-map"))

            assert text(doc, "main h1") ==
                     if(@page["status"] == 401,
                       do: text(LazyHTML.from_fragment(rails), "h1"),
                       else:
                         DawarichWeb.Translate.t(
                           @page["html_lang"],
                           "shared.links.not_found.this_shared_link_is_no_longer_available",
                           %{}
                         )
                     )
          end
        else
          assert text(doc, "h1") == text(LazyHTML.from_fragment(rails), "h1")
          assert text(doc, "main") == text(LazyHTML.from_fragment(rails), "main")
          assert html =~ ~s(<html lang="#{@page["html_lang"]}">)
        end
      end
    end
  end

  @static_classes %{
    "text-3xl font-bold leading-tight min-w-0 max-w-full [overflow-wrap:anywhere]" =>
      "text-3xl font-bold leading-tight",
    "text-3xl font-bold mb-2 min-w-0 max-w-full [overflow-wrap:anywhere]" =>
      "text-3xl font-bold mb-2",
    "collapse-title flex flex-wrap min-w-0 items-center gap-2 text-sm font-medium min-h-0 cursor-pointer" =>
      "collapse-title flex items-center gap-2 text-sm font-medium min-h-0 cursor-pointer",
    "container mx-auto px-4 my-5 min-w-0 [overflow-wrap:anywhere]" =>
      "container mx-auto px-4 my-5",
    "container mx-auto px-4 py-6 min-w-0 [overflow-wrap:anywhere]" =>
      "container mx-auto px-4 py-6",
    "w-full lg:w-3/5 h-[50vh] lg:h-full shrink-0 relative" =>
      "w-full lg:w-3/5 h-[50vh] lg:h-full shrink-0",
    "flex flex-wrap min-w-0 items-start justify-between gap-3 mb-1" =>
      "flex items-start justify-between gap-3 mb-1",
    "bg-base-200 rounded-lg px-4 py-3 flex flex-wrap min-w-0 items-center gap-2 text-sm font-medium cursor-pointer transition-colors hover:bg-base-300" =>
      "bg-base-200 rounded-lg px-4 py-3 flex items-center gap-2 text-sm font-medium cursor-pointer transition-colors hover:bg-base-300"
  }
  defp static_dom(html, selector) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> LazyHTML.to_tree()
    |> static_tree()
    |> Dawarich.Test.ParityHTML.normalize()
  end

  defp static_tree(nodes) when is_list(nodes) do
    nodes = Enum.reject(nodes, &(is_binary(&1) and String.trim(&1) == ""))
    static_siblings(nodes)
  end

  defp static_tree({tag, attrs, children}) do
    day = Map.new(attrs)["id"] || ""

    attrs =
      if Map.new(attrs)["phx-hook"] == "PublicMap",
        do: Enum.reject(attrs, &(&1 == {"style", ""})),
        else: attrs

    attrs =
      Enum.flat_map(attrs, fn
        {key, _} = attr when key in ["role", "tabindex"] ->
          if String.starts_with?(day, "native-public-day-"), do: [], else: [attr]

        {"id", "shared-trip-map"} ->
          [{"id", "native-public-map"}]

        {"class", value} ->
          [{"class", Map.get(@static_classes, value, value)}]

        {"data-public-day", value} ->
          if Map.new(attrs)["phx-click"] == "public:day", do: [{"data-day-key", value}], else: []

        {"data-public-" <> key, value} ->
          [{"data-native-public-" <> key, value}]

        attr ->
          [attr]
      end)

    {tag, attrs, static_tree(children)}
  end

  defp static_tree(text), do: text

  defp static_siblings([{"div", attrs, children} = map, {"div", replay_attrs, _} = replay | rest]) do
    if Map.new(attrs)["phx-hook"] == "PublicMap" and
         Map.new(replay_attrs)["id"] == "native-public-replay" do
      [static_tree({"div", attrs, children ++ [replay]}) | static_siblings(rest)]
    else
      [static_tree(map) | static_siblings([replay | rest])]
    end
  end

  defp static_siblings([first | rest]), do: [static_tree(first) | static_siblings(rest)]
  defp static_siblings([]), do: []
end
