defmodule DawarichWeb.TripsIndexParityTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest

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

  for page <-
        "test/fixtures/trips/pages.json" |> File.read!() |> Jason.decode!() |> Map.fetch!("pages"),
      String.starts_with?(page["name"], "index_") do
    @page page

    test "#{page["name"]} matches the page Rails renders" do
      html = RailsUser.signed_in(@page["user_id"]) |> get(@page["path"]) |> html_response(200)
      rails = @dir |> Path.join("pages/#{@page["name"]}.html") |> File.read!()
      title = @page["title"] |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

      assert ParityHTML.fragment(html, "div.px-4.flex-1 > div.flex > *") ==
               ParityHTML.normalize(rails)

      assert previews(html) == previews("<html><body>#{rails}</body></html>")
      assert html =~ ">#{title}</title>"
    end
  end

  defp previews(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("#trips [data-controller]")
    |> LazyHTML.to_tree()
    |> Enum.map(fn {_tag, attrs, _children} ->
      attrs |> Enum.filter(&String.starts_with?(elem(&1, 0), "data-")) |> Enum.sort()
    end)
  end
end
