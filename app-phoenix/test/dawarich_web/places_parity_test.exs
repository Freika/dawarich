defmodule DawarichWeb.PlacesParityTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  alias Dawarich.Test.{FrameSeeds, MapStimulus, ParityHTML, RailsUser}
  alias DawarichWeb.MapFrames

  @endpoint DawarichWeb.Endpoint
  @dir "test/fixtures/places"
  @names ~w(drawer_empty drawer_full drawer_gpx drawer_signed_out drawer_utc list_blank_zone
            list_empty list_extra list_foreign list_no_zone list_page0 list_page1 list_page2
            list_page_2abc list_page_blank list_page_out list_page_space list_utc)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    saved = System.get_env("TIME_ZONE")
    System.delete_env("TIME_ZONE")
    on_exit(fn -> if saved, do: System.put_env("TIME_ZONE", saved) end)
  end

  defp load(name), do: "#{@dir}/#{name}.json" |> File.read!() |> Jason.decode!()

  test "the corpus is complete" do
    assert @dir
           |> Path.join("*.json")
           |> Path.wildcard()
           |> Enum.reject(&String.starts_with?(Path.basename(&1), "a12f3a-"))
           |> Enum.map(&Path.basename(&1, ".json"))
           |> Enum.sort() == @names
  end

  for name <- @names do
    @name name

    test "#{@name} preserves source values and retained transport" do
      unless @name == "list_foreign", do: FrameSeeds.seed!(load("list_foreign"))
      state = load(@name)
      user = FrameSeeds.seed!(state)
      check(state, user, File.read!(Path.join(@dir, @name <> ".html")))
    end
  end

  defp check(%{"kind" => "list"} = state, user, rails) do
    html = RailsUser.signed_in(user.id) |> get(state["path"]) |> html_response(200)
    title = state["title"] |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    assert cells(html) == cells(rails)
    assert page_links(html) == page_links(rails)
    assert html =~ "data-native-places"
    refute html =~ "data-turbo-method"

    assert LazyHTML.query(LazyHTML.from_document(html), "#places script, #places b")
           |> Enum.empty?()

    assert html =~ ">#{title}</title>"
  end

  defp check(%{"kind" => "drawer", "status" => 200} = state, user, rails) do
    ctx = %{
      user: user,
      locale: DawarichWeb.Locale.resolve(nil, user, %{}),
      id: state["path"] |> String.split("/") |> List.last(),
      csrf: "CSRF",
      csrf_changes: %{}
    }

    assert {:ok, "text/html", body} = MapFrames.body(:place, ctx)
    body = IO.iodata_to_binary(body)

    assert ParityHTML.normalize(body) == ParityHTML.normalize(rails)

    assert stimulus(body, "#place-drawer") == stimulus(rails, "#place-drawer")

    conn = state |> frame_conn(RailsUser.signed_in(user.id)) |> get(state["path"])

    assert conn.status == state["status"]

    assert conn |> get_resp_header("content-type") |> hd() |> String.split(";") |> hd() ==
             state["content_type"]

    assert get_resp_header(conn, "vary") == List.wrap(state["vary"])
  end

  defp check(%{"kind" => "drawer", "status" => 302} = state, nil, _rails) do
    conn = state |> frame_conn(build_conn()) |> get(state["path"])

    assert redirected_to(conn, 302) == state["location"]

    [_, value] =
      Regex.run(~r/_dawarich_session=([^;]+)/, conn |> get_resp_header("set-cookie") |> hd())

    staged =
      build_conn()
      |> put_req_cookie("_dawarich_session", value)
      |> DawarichWeb.RailsAuth.call([])
      |> Map.fetch!(:assigns)
      |> Map.fetch!(:rails_session)

    assert %{
             "user_return_to" => staged["user_return_to"],
             "alert" => get_in(staged, ["flash", "flashes", "alert"])
           } == state["session"]
  end

  defp cells(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("tbody tr")
    |> Enum.map(fn row ->
      row
      |> LazyHTML.query("td")
      |> Enum.take(3)
      |> Enum.map(&(LazyHTML.text(&1) |> String.trim()))
    end)
  end

  defp page_links(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("a[href]")
    |> LazyHTML.attribute("href")
    |> Enum.filter(&String.starts_with?(&1, "/places?page="))
  end

  defp stimulus(html, region),
    do: html |> MapStimulus.attributes([region]) |> Enum.filter(&match?({^region, _, _}, &1))

  defp frame_conn(state, conn),
    do:
      conn
      |> put_req_header("accept", state["accept"])
      |> put_req_header("turbo-frame", "place-drawer")
end
