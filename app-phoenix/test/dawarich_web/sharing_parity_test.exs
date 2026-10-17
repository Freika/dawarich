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
            assert text(doc, "main h1") == link["name"]
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
end
