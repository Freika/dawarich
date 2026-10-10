defmodule DawarichWeb.TripsShowParityTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Dawarich.Test.FormIsolation

  alias Dawarich.Test.{MapStimulus, ParityHTML, RailsUser, TripsSeeds}

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

    test "#{page["name"]} matches the page Rails renders" do
      html =
        RailsUser.signed_in(@page["user_id"])
        |> get(@page["path"])
        |> html_response(200)
        |> MapStimulus.prepare()

      rails =
        @dir |> Path.join("pages/#{@page["name"]}.html") |> File.read!() |> MapStimulus.prepare()

      assert_form_isolated(html)

      title = @page["title"] |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

      assert ParityHTML.fragment(html, "div.px-4.flex-1 > div.flex > *") ==
               ParityHTML.normalize(rails)

      content =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("div.px-4.flex-1 > div.flex > *")
        |> LazyHTML.to_html()

      assert MapStimulus.attributes("<html><body>#{content}</body></html>", ["#trip-shell"]) ==
               MapStimulus.attributes("<html><body>#{rails}</body></html>", ["#trip-shell"])

      assert html =~ ">#{title}</title>"
    end
  end
end
