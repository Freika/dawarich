defmodule DawarichWeb.ImportsExportsParityTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Dawarich.Test.{ImportsExportsSeeds, ParityHTML, RailsUser}

  @endpoint DawarichWeb.Endpoint
  @dir "test/fixtures/imports_exports"
  @external_resource "test/fixtures/imports_exports/pages.json"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    seed = @dir |> Path.join("seed.json") |> File.read!() |> Jason.decode!()
    ImportsExportsSeeds.load!(seed, NaiveDateTime.utc_now())
    :ok
  end

  for page <- "test/fixtures/imports_exports/pages.json" |> File.read!() |> Jason.decode!() do
    @page page

    test "#{page["name"]} matches the page Rails renders" do
      html = get(RailsUser.signed_in(@page["user_id"]), @page["path"]) |> html_response(200)
      rails = File.read!(Path.join(@dir, "pages/#{@page["name"]}.html"))

      assert ParityHTML.fragment(html, "div.px-4.flex-1 > div.flex > *") ==
               ParityHTML.normalize(rails)

      assert html =~ "<title>#{@page["title"]}</title>"
    end
  end
end
