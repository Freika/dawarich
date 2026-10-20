defmodule DawarichWeb.TripsShowParityTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Dawarich.Test.{NativeTripCorpus, ParityHTML, RailsUser, TripsSeeds}

  @endpoint DawarichWeb.Endpoint
  @dir "test/fixtures/trips"
  @external_resource "test/fixtures/trips/pages.json"
  @env ~w(PRINT_ORDER_URL TIME_ZONE)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    saved = Map.new(@env, &{&1, System.get_env(&1)})
    Enum.each(@env, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(saved, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    TripsSeeds.load!(
      @dir |> Path.join("seed.json") |> File.read!() |> Jason.decode!(),
      NaiveDateTime.utc_now()
    )

    :ok
  end

  test "native trip destructive actions require confirmation and cancel keeps the trip" do
    conn = RailsUser.signed_in(9803) |> RailsUser.connecting_as(9803)
    {:ok, view, _} = live(conn, "/trips/980301")
    render_click(view, "trip:delete", %{})

    assert Dawarich.Repo.query!("SELECT id FROM trips WHERE id=980301", [], log: false).num_rows ==
             1

    assert has_element?(view, "#native-trip-confirmation[role=dialog]")
    render_click(view, "trip:confirmation:cancel", %{})
    refute has_element?(view, "#native-trip-confirmation")

    assert Dawarich.Repo.query!("SELECT id FROM trips WHERE id=980301", [], log: false).num_rows ==
             1

    render_click(view, "trip:delete", %{})
    render_click(view, "trip:confirmation:accept", %{})
    assert_redirect(view, "/trips")

    assert Dawarich.Repo.query!("SELECT id FROM trips WHERE id=980301", [], log: false).num_rows ==
             0
  end

  test "Rails 1.16.0 new and edit trip forms preserve fields preview and actions" do
    pages = @dir |> Path.join("pages.json") |> File.read!() |> Jason.decode!()

    for page <- Enum.sort_by(pages["pages"], &String.contains?(&1["path"], "locale=")),
        String.starts_with?(page["name"], "form_") do
      html = RailsUser.signed_in(page["user_id"]) |> get(page["path"]) |> html_response(200)
      rails = @dir |> Path.join("pages/#{page["name"]}.html") |> File.read!()
      actual = form_dom(html)
      expected = form_dom(rails)

      assert actual == expected,
             page["name"] <> ": " <> ParityHTML.first_difference(actual, expected)
    end
  end

  defp form_dom(html) do
    doc = LazyHTML.from_document(html)
    root = doc |> LazyHTML.query(".mx-auto.my-5.md\\:w-2\\/3") |> LazyHTML.to_tree()
    assert root != []
    root |> form_nodes() |> ParityHTML.normalize()
  end

  defp form_nodes(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &form_node/1)

  defp form_node({"input", attrs, _} = node) do
    values = Map.new(attrs)

    cond do
      values["data-datetime-target"] == "apiKey" -> []
      values["name"] == "trip[description]" -> []
      true -> [node]
    end
  end

  defp form_node({"trix-editor", attrs, _}) do
    assert Map.new(attrs)["class"] == "trix-content-editor"
    [{"native-rich-editor", [], []}]
  end

  defp form_node({tag, attrs, children}) do
    if Map.new(attrs)["id"] == "trip-description" do
      for {"trix-editor", editor_attrs, _} <- children,
          do: assert(Map.new(editor_attrs)["class"] == "trix-content-editor")

      [{"native-rich-editor", [], []}]
    else
      [{tag, attrs, form_nodes(children)}]
    end
  end

  defp form_node(other), do: [other]

  test "Rails 1.16.0 trip detail preserves header toolbar days notes and description DOM" do
    pages = @dir |> Path.join("pages.json") |> File.read!() |> Jason.decode!()

    for page <- pages["pages"], String.starts_with?(page["name"], "show_") do
      html = RailsUser.signed_in(page["user_id"]) |> get(page["path"]) |> html_response(200)
      rails = @dir |> Path.join("pages/#{page["name"]}.html") |> File.read!()
      actual = detail_dom(html)
      expected = detail_dom(rails)

      assert actual == expected,
             page["name"] <> ": " <> ParityHTML.first_difference(actual, expected)
    end
  end

  defp detail_nodes(nodes), do: Enum.flat_map(nodes, &detail_node/1)

  defp detail_node({tag, attrs, children}) do
    values = Map.new(attrs)

    cond do
      values["id"] == "native-trip-summary" ->
        assert values["class"] == "contents"
        detail_nodes(children)

      Map.has_key?(values, "data-note-form") and values["class"] == "hidden" ->
        []

      tag == "input" and values["type"] == "hidden" and values["name"] == "day" ->
        []

      true ->
        attrs =
          Enum.map(attrs, fn
            {"class", value} ->
              {"class", detail_class(value)}

            {"href", value} ->
              {"href",
               if(Regex.match?(~r{^/trips/\d+/export\?file_format=(gpx|json)$}, value),
                 do: "#",
                 else: value
               )}

            pair ->
              pair
          end)

        [{tag, attrs, detail_nodes(children)}]
    end
  end

  defp detail_node(other), do: [other]

  defp detail_class(value) do
    value
    |> String.replace("w-full min-w-0 lg:w-2/5", "w-full lg:w-2/5")
    |> String.replace(
      "flex flex-wrap items-start justify-between gap-3 mb-1",
      "flex items-start justify-between gap-3 mb-1"
    )
    |> String.replace(
      "flex flex-wrap items-center gap-1 shrink-0",
      "flex items-center gap-1 shrink-0"
    )
    |> String.replace("leading-tight min-w-0 [overflow-wrap:anywhere]", "leading-tight")
    |> String.replace("collapse-title flex flex-wrap", "collapse-title flex")
    |> String.replace("prose max-w-none [overflow-wrap:anywhere]", "prose max-w-none")
  end

  defp detail_dom(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("#trip-shell .lg\\:w-2\\/5")
    |> LazyHTML.to_tree()
    |> detail_nodes()
    |> ParityHTML.normalize()
  end

  for page <-
        "test/fixtures/trips/pages.json" |> File.read!() |> Jason.decode!() |> Map.fetch!("pages"),
      String.starts_with?(page["name"], "show_") do
    @page page

    test "#{page["name"]} retains native source text values days notes and cookie reads" do
      conn = RailsUser.signed_in(@page["user_id"]) |> get(@page["path"])
      html = html_response(conn, 200)
      rails = @dir |> Path.join("pages/#{@page["name"]}.html") |> File.read!()
      NativeTripCorpus.assert_values(html, rails)
      title = @page["title"] |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      assert html =~ ">#{title}</title>"
      refute html =~ "data-controller"
      refute html =~ "data-action"
      refute html =~ "turbo-cable-stream-source"
      refute html =~ "a8-k-"

      id = @page["path"] |> String.split("/") |> List.last()

      data =
        RailsUser.signed_in(@page["user_id"])
        |> get("/native/map/data/trips/#{id}")
        |> json_response(200)

      [path] =
        NativeTripCorpus.attrs(
          rails,
          "[data-controller=trip-maplibre]",
          "data-trip-maplibre-path-data-value"
        )

      [windows] =
        NativeTripCorpus.attrs(
          rails,
          "[data-controller=trip-maplibre]",
          "data-trip-maplibre-device-windows-value"
        )

      assert data["path"] == Jason.decode!(path)
      assert data["deviceWindows"] == Jason.decode!(windows)
      refute Map.has_key?(data, "api_key")
    end
  end
end
