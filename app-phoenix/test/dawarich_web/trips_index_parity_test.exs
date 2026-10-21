defmodule DawarichWeb.TripsIndexParityTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Dawarich.Test.{ParityHTML, RailsUser, TripsSeeds}

  @endpoint DawarichWeb.Endpoint
  @dir "test/fixtures/trips"
  @external_resource "test/fixtures/trips/pages.json"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    saved = System.get_env("TIME_ZONE")
    System.delete_env("TIME_ZONE")
    on_exit(fn -> if saved, do: System.put_env("TIME_ZONE", saved) end)

    TripsSeeds.load!(
      @dir |> Path.join("seed.json") |> File.read!() |> Jason.decode!(),
      NaiveDateTime.utc_now()
    )

    :ok
  end

  test "trip index uses the application shell without a second page padding layer" do
    html = RailsUser.signed_in(9805) |> get("/trips") |> html_response(200)
    dom = LazyHTML.from_document(html)
    assert Enum.count(LazyHTML.query(dom, ".container > .navbar")) == 1

    assert Enum.count(LazyHTML.query(dom, ".w-full.px-4 > .flex > #native-trips-index.contents")) ==
             1

    assert Enum.count(LazyHTML.query(dom, "footer")) == 1
    refute html =~ ~s(id="native-trips-index" class="w-full min-w-0 p-4")
  end

  test "trip pagination retains harmless extras without retaining credential query fields" do
    conn = RailsUser.signed_in(9805) |> RailsUser.connecting_as(9805)

    {:ok, view, _} =
      live(conn, "/trips?page=2&view=cards&locale=en&access_token=synthetic-query-value")

    query = :sys.get_state(view.pid).socket.assigns.query
    keys = Map.keys(query)
    refute "access_token" in keys
    assert query["view"] == "cards"
    assert query["locale"] == "en"
    refute has_element?(view, "#trips [role=navigation] a[href*=access_token]")
  end

  test "Rails 1.16.0 trip index DOM preserves filters empty states and preview shells" do
    pages = @dir |> Path.join("pages.json") |> File.read!() |> Jason.decode!()

    for page <- Enum.sort_by(pages["pages"], &String.contains?(&1["path"], "locale=")),
        String.starts_with?(page["name"], "index_") do
      html = RailsUser.signed_in(page["user_id"]) |> get(page["path"]) |> html_response(200)
      rails = @dir |> Path.join("pages/#{page["name"]}.html") |> File.read!()
      actual = index_dom(html)
      expected = index_dom(rails)

      assert actual == expected,
             page["name"] <> ": " <> ParityHTML.first_difference(actual, expected)
    end
  end

  defp index_dom(html) do
    html
    |> String.replace(~r/\b(selected|disabled)="\1"/, "\\1=\"\"")
    |> ParityHTML.fragment("#trips")
  end

  for page <-
        "test/fixtures/trips/pages.json" |> File.read!() |> Jason.decode!() |> Map.fetch!("pages"),
      String.starts_with?(page["name"], "index_") do
    @page page

    test "#{page["name"]} preserves native card values ordering pagination and previews" do
      html = RailsUser.signed_in(@page["user_id"]) |> get(@page["path"]) |> html_response(200)
      rails = @dir |> Path.join("pages/#{@page["name"]}.html") |> File.read!()
      title = @page["title"] |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

      actual = LazyHTML.from_document(html)
      expected = LazyHTML.from_fragment(rails)

      for selector <- [
            "#trips h1",
            "#trips h3",
            "#trips [data-trip-id]",
            "#trips [role=navigation]"
          ] do
        assert values(actual, selector) == values(expected, selector)
      end

      assert LazyHTML.query(actual, "#trips [data-trip-id]") |> LazyHTML.attribute("data-trip-id") ==
               LazyHTML.query(expected, "#trips [data-trip-id]")
               |> LazyHTML.attribute("data-trip-id")

      assert pagination(actual) == pagination(expected)

      if @page["name"] == "index_many_extra_param" do
        native_links =
          LazyHTML.query(actual, "#trips [role=navigation] a") |> LazyHTML.attribute("href")

        assert Enum.any?(
                 LazyHTML.query(expected, "#trips [role=navigation] a")
                 |> LazyHTML.attribute("href"),
                 &String.contains?(&1, "view=cards")
               )

        assert native_links != []
        assert Enum.any?(native_links, &String.contains?(&1, "view=cards"))
      end

      assert previews(actual, "[phx-hook=MapPreview]", "data-map-config") ==
               previews(expected, "[data-controller=trip-maplibre-preview]", nil)

      assert Enum.count(LazyHTML.query(actual, "#native-trips-index")) == 1
      assert Enum.empty?(LazyHTML.query(actual, "[data-controller], turbo-frame"))
      assert html =~ ">#{title}</title>"
    end
  end

  defp values(doc, selector),
    do:
      Enum.map(
        LazyHTML.query(doc, selector),
        &(LazyHTML.text(&1) |> String.replace(~r/\s+/, " ") |> String.trim())
      )

  defp pagination(doc) do
    for node <- LazyHTML.query(doc, "#trips [role=navigation] a") do
      [href] = LazyHTML.attribute(node, "href")
      uri = URI.parse(href)

      {String.trim(LazyHTML.text(node)), uri.path,
       URI.decode_query(uri.query || "") |> Map.take(~w(page family_page))}
    end
  end

  defp previews(doc, selector, attribute) do
    for card <- LazyHTML.query(doc, "#trips [data-trip-id]"),
        node <- LazyHTML.query(card, selector) do
      [id] = LazyHTML.attribute(card, "data-trip-id")

      style =
        if attribute do
          [json] = LazyHTML.attribute(node, attribute)
          config = Jason.decode!(json)
          assert config["tripId"] == String.to_integer(id)
          assert config["interactive"] == false
          refute Map.has_key?(config, "path")
          config["styleName"]
        else
          LazyHTML.attribute(node, "data-trip-maplibre-preview-map-style-value") |> hd()
        end

      {id, style}
    end
  end
end
