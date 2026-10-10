defmodule DawarichWeb.TripsShowParityTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest

  alias Dawarich.Test.{NativeTripCorpus, RailsUser, TripsSeeds}

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
