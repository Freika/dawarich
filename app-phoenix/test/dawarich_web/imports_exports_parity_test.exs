defmodule DawarichWeb.ImportsExportsParityTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias Dawarich.Test.{
    ImportsExportsSeeds,
    ParityHTML,
    RailsUser,
    NativeImportCorpus,
    NativeExportCorpus
  }

  @endpoint DawarichWeb.Endpoint
  @dir "test/fixtures/imports_exports"
  @external_resource "test/fixtures/imports_exports/pages.json"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    seed = @dir |> Path.join("seed.json") |> File.read!() |> Jason.decode!()
    ImportsExportsSeeds.load!(seed, NaiveDateTime.utc_now())
    :ok
  end

  for page <- "test/fixtures/imports_exports/pages.json" |> File.read!() |> Jason.decode!(),
      query = URI.parse(page["path"]).query || "",
      not Enum.any?(String.split(query, "&", trim: true), &(not String.contains?(&1, "="))) do
    @page page

    test "#{page["name"]} retains index business text fields links and title" do
      html = get(RailsUser.signed_in(@page["user_id"]), @page["path"]) |> html_response(200)
      rails = File.read!(Path.join(@dir, "pages/#{@page["name"]}.html"))

      if String.starts_with?(@page["path"], "/imports") do
        NativeImportCorpus.assert_page(html, rails)
      else
        NativeExportCorpus.assert_page(html, rails)
      end

      selector =
        if String.starts_with?(@page["path"], "/imports"),
          do: "[data-testid=native-imports-root]",
          else: "[data-testid=native-exports-root]"

      native = Dawarich.Test.DataPageParity.action_paths(html)

      native =
        Regex.replace(
          ~r/(<button[^>]*data-testid="import-delete"[^>]*?) aria-label="[^"]*"/,
          native,
          "\\1"
        )

      native =
        Regex.replace(
          ~r/(<a[^>]*href="\/exports\/[0-9]+"[^>]*?) aria-label="[^"]*"/,
          native,
          "\\1"
        )

      native = ParityHTML.without(native, ["dialog"], selector)
      expected = ParityHTML.normalize(rails)
      assert native == expected, ParityHTML.first_difference(native, expected)

      assert html =~ ">#{@page["title"]}</title>"
    end
  end

  test "native data action links retain their Rails routes without document navigation" do
    now = NaiveDateTime.utc_now()

    Dawarich.Repo.insert_all("notifications", [
      %{
        id: 97_010_990,
        user_id: 9701,
        title: "Action route",
        content: "Synthetic notification",
        kind: 0,
        created_at: now,
        updated_at: now
      }
    ])

    Dawarich.Test.FrameSeeds.place!(9701, 97_010_990, "Synthetic action place")

    for {id, path} <- [
          {9707, "/imports"},
          {9701, "/exports"},
          {9701, "/notifications"},
          {9701, "/places"},
          {9701, "/points"}
        ] do
      html = get(RailsUser.signed_in(id), path) |> html_response(200)
      controls = html |> LazyHTML.from_document() |> LazyHTML.query("a[phx-click]")
      assert Enum.count(controls) > 0, path

      for control <- controls do
        assert LazyHTML.attribute(control, "href") == ["#"], path
        assert [route] = LazyHTML.attribute(control, "data-native-href")
        assert String.starts_with?(route, "/"), path
      end
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
