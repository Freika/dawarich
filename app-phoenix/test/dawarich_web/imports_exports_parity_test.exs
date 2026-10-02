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

      native = ParityHTML.fragment(html, "div.px-4.flex-1 > div.flex > *")
      expected = ParityHTML.normalize(rails)

      assert native == expected,
             "#{@page["name"]}: " <> ParityHTML.first_difference(native, expected)

      assert html =~ "<title>#{@page["title"]}</title>"
    end
  end

  test "delete action normalization retains route method confirmation visuals and accessibility" do
    rails =
      ~s(<a href="/imports/12" data-turbo-method="delete" data-turbo-confirm="Sure?" class="btn" aria-label="Delete"><svg class="icon"><path d="M1 2" /></svg>Delete</a>)

    native =
      ~s(<form action="/imports/12" method="post" phx-submit="delete_import"><input type="hidden" name="authenticity_token" value="token" /><input type="hidden" name="_method" value="delete" /><input type="hidden" name="import_id" value="12" /><button type="submit" class="btn" aria-label="Delete" data-confirm="Sure?" data-testid="import-delete"><svg class="icon"><path d="M1 2" /></svg>Delete</button></form>)

    expected = ParityHTML.normalize(rails)
    assert ParityHTML.normalize(native) == expected

    for {from, to} <- [
          {~s(action="/imports/12"), ~s(action="/imports/13")},
          {~s(method="post"), ~s(method="get")},
          {~s(value="delete"), ~s(value="patch")},
          {~s(data-confirm="Sure?"), ~s(data-confirm="Different?")},
          {~s(d="M1 2"), ~s(d="M3 4")},
          {~s(class="icon"), ~s(class="hidden")},
          {~s(class="btn"), ~s(class="btn-error")},
          {~s(aria-label="Delete"), ~s(aria-label="Edit")},
          {">Delete</button>", ">Edit</button>"},
          {~s(name="import_id" value="12"), ~s(name="import_id" value="13")},
          {~s(name="authenticity_token"), ~s(name="missing_token")},
          {~s(name="_method"), ~s(name="_method" disabled)},
          {~s(value="token"), ~s(value="")},
          {~s(type="submit"), ~s(type="reset")},
          {~s(aria-label="Delete"), ~s(aria-label="Delete" tabindex="-1")},
          {~s(aria-label="Delete"), ~s(aria-label="Delete" disabled)}
        ] do
      refute ParityHTML.normalize(String.replace(native, from, to)) == expected,
             "normalizer must retain #{from}"
    end
  end

  test "Rails action mutations remain visible to equivalent action comparison" do
    rails =
      ~s(<a href="/imports/12" data-turbo-method="delete" data-turbo-confirm="Sure?" class="btn">Delete</a>)

    expected = ParityHTML.normalize(rails)

    for {from, to} <- [
          {~s(data-turbo-method="delete"), ~s(data-turbo-method="patch")},
          {~s(data-turbo-confirm="Sure?"), ~s(data-turbo-confirm="Changed?")},
          {~s(href="/imports/12"), ~s(href="/imports/13")}
        ] do
      refute ParityHTML.normalize(String.replace(rails, from, to)) == expected
    end
  end
end
