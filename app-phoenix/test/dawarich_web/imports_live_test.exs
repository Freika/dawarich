defmodule DawarichWeb.ImportsLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Dawarich.Test.RailsUser
  alias Dawarich.Test.ImportsExportsSeeds, as: Seeds
  alias DawarichWeb.RailsCsrf

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)

    user =
      RailsUser.insert!(%{
        id: 7101,
        email: "a7-imports-live@dawarich.test",
        settings: %{"timezone" => "Europe/Berlin"}
      })

    %{user: user}
  end

  defp live_as(user, path \\ "/imports"),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

  describe "route" do
    test "a signed-in user gets the page under Rails' title", %{user: user} do
      {:ok, _view, html} = live_as(user)
      assert html =~ ">Imports | Dawarich</title>"
    end

    test "a signed-out visitor is sent to Rails' sign-in page" do
      assert redirected_to(get(build_conn(), "/imports?page=2"), 302) ==
               "http://www.example.com/users/sign_in"
    end

    test "HEAD answers without a body", %{user: user} do
      conn = head(RailsUser.signed_in(user.id), "/imports")
      assert {conn.status, conn.resp_body} == {200, ""}
    end
  end

  defp content(html),
    do: html |> LazyHTML.from_document() |> LazyHTML.query("div.px-4.flex-1 div.w-full.my-5")

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  defp row_ids(doc), do: doc |> LazyHTML.query("#imports tbody tr") |> LazyHTML.attribute("id")

  defp at(hours_ago), do: NaiveDateTime.add(NaiveDateTime.utc_now(), -hours_ago * 3600)

  describe "list" do
    test "an empty list shows Rails' empty state and the single New import button", %{user: user} do
      {:ok, _view, html} = live_as(user)
      page = content(html)

      assert html =~ "No imports yet"
      assert count(page, "#imports h3") == 1
      assert count(page, ~s(#imports a.btn.btn-primary[href="/imports/new"])) == 1
      assert count(page, ~s(a.btn.btn-primary.btn-sm[href="/imports/new"])) == 1
      assert count(page, "#imports table, .join, .dropdown") == 0
    end

    test "lists only the signed-in user's imports, newest first", %{user: user} do
      other = Seeds.user!(7102, %{})
      Seeds.import!(%{id: 710_101, user_id: user.id, name: "older", created_at: at(2)})
      Seeds.import!(%{id: 710_102, user_id: user.id, name: "newer", created_at: at(1)})
      Seeds.import!(%{id: 710_201, user_id: other.id, name: "foreign", created_at: at(0)})

      {:ok, _view, html} = live_as(user)
      assert row_ids(content(html)) == ["import_710102", "import_710101"]
    end

    test "row actions retain native read links and delete uses a LiveView form with a native HTTP fallback",
         %{user: user} do
      Seeds.import!(%{id: 710_111, user_id: user.id, created_at: at(1)})
      Seeds.file!("Import", 710_111, "file", 971_111, 2048, "a.gpx")

      {:ok, _view, html} = live_as(user)
      page = content(html)

      for selector <- [
            ~s(a.link.link-hover[href="/imports/710111"]),
            ~s(a.btn.btn-ghost.btn-xs[href="/map/v2?import_id=710111"]),
            ~s(a.btn.btn-ghost.btn-xs[href="/points?import_id=710111"]),
            ~s(a.btn.btn-ghost.btn-xs[href="/imports/710111/download"][data-turbo="false"]),
            ~s(form[action="/imports/710111"][phx-submit="delete_import"] button[data-testid="import-delete"][data-confirm="Are you sure?"])
          ],
          do: assert(count(page, selector) == 1, selector)

      assert count(page, ~s(form[phx-submit="delete_import"])) == 1
      assert count(page, "[data-turbo-method=delete]") == 0
    end

    test "only an original file gets a download link; a prepared download alone does not",
         %{user: user} do
      Seeds.import!(%{id: 710_121, user_id: user.id, created_at: at(1)})
      Seeds.file!("Import", 710_121, "prepared_download", 971_121, 4096, "b.zip")

      {:ok, _view, html} = live_as(user)
      page = content(html)

      assert count(page, ~s(a[href$="/download"])) == 0

      assert page
             |> LazyHTML.query("#import_710121 td:nth-child(2)")
             |> LazyHTML.text()
             |> String.trim() == "N/A"
    end

    test "a deleting import shows the spinner for an hour after its last update, then the stalled retry",
         %{user: user} do
      now = NaiveDateTime.utc_now()

      Seeds.import!(%{
        id: 710_131,
        user_id: user.id,
        status: 4,
        updated_at: NaiveDateTime.add(now, -3590),
        created_at: at(1)
      })

      Seeds.import!(%{
        id: 710_132,
        user_id: user.id,
        status: 4,
        updated_at: NaiveDateTime.add(now, -3610),
        created_at: at(2)
      })

      {:ok, _view, html} = live_as(user)
      page = content(html)

      assert count(page, "#import_710131 .loading-spinner") == 1
      assert count(page, "#import_710131 a") == 1
      assert count(page, "#import_710132 .loading-spinner") == 0

      assert count(page, ~s(#import_710132 .tooltip-left button[data-testid="import-delete"])) ==
               1

      assert count(page, ~s(#import_710132 a[href^="/map/v2"])) == 0
    end

    test "the header offers Immich and PhotoPrism imports only with both a URL and an API key",
         %{user: user} do
      immich = %{"immich_url" => "https://i.example", "immich_api_key" => "k"}
      photoprism = %{"photoprism_url" => "https://p.example", "photoprism_api_key" => "k"}

      cases = [
        {user, []},
        {Seeds.user!(7103, immich), ["start_immich_import"]},
        {Seeds.user!(7104, Map.merge(immich, photoprism)),
         ["start_immich_import", "start_photoprism_import"]},
        {Seeds.user!(7105, %{"immich_url" => "https://i.example", "immich_api_key" => "  "}), []}
      ]

      for {owner, jobs} <- cases do
        {:ok, _view, html} = live_as(owner)
        page = content(html)

        hrefs =
          page
          |> LazyHTML.query(
            ~s(.dropdown-content a[data-turbo-method="post"][data-turbo-confirm="Are you sure?"])
          )
          |> LazyHTML.attribute("href")

        assert hrefs == Enum.map(jobs, &("/settings/background_jobs?job_name=" <> &1)),
               inspect(jobs)

        assert count(page, ".join") == if(jobs == [], do: 0, else: 1)
      end
    end

    test "sort headers and the paginator carry Rails' query strings", %{user: user} do
      for n <- 1..27,
          do:
            Seeds.import!(%{
              id: 710_300 + n,
              user_id: user.id,
              name: "n#{100 + n}",
              created_at: at(n)
            })

      {:ok, _view, html} = live_as(user, "/imports?order_by=asc&sort_by=name&page=2")
      page = content(html)

      assert count(page, ~s(th a.font-bold[href="/imports?order_by=desc&sort_by=name"])) == 1
      assert count(page, ~s(th a[href="/imports?order_by=asc&sort_by=created_at"])) == 1
      assert count(page, ~s(a.join-item[href="/imports?order_by=asc&sort_by=name"])) == 4
      assert row_ids(page) == ["import_710326", "import_710327"]
    end

    test "a page patch reads the list again", %{user: user} do
      for n <- 1..26, do: Seeds.import!(%{id: 710_400 + n, user_id: user.id, created_at: at(n)})

      {:ok, view, _html} = live_as(user)

      assert view |> render_patch("/imports?page=2") |> LazyHTML.from_fragment() |> row_ids() == [
               "import_710426"
             ]
    end

    test "the table body keeps Rails' Stimulus attributes", %{user: user} do
      Seeds.import!(%{id: 710_141, user_id: user.id})
      {:ok, _view, html} = live_as(user)

      assert count(
               content(html),
               ~s(tbody[data-controller="imports"][data-imports-target="index"][data-user-id="7101"])
             ) == 1
    end

    test "a failed import shows its error in a tooltip; a blank error shows none", %{user: user} do
      Seeds.import!(%{
        id: 710_151,
        user_id: user.id,
        status: 3,
        error_message: "Bad <b>file</b>",
        created_at: at(1)
      })

      Seeds.import!(%{
        id: 710_152,
        user_id: user.id,
        status: 3,
        error_message: "   ",
        created_at: at(2)
      })

      {:ok, _view, html} = live_as(user)
      page = content(html)

      assert page
             |> LazyHTML.query("#import_710151 .cursor-help")
             |> LazyHTML.attribute("data-tip") ==
               ["Bad <b>file</b>"]

      assert count(page, "#import_710152 .cursor-help") == 0
    end
  end

  describe "without a socket" do
    test "the dead render carries the delete link and the Rails CSRF meta A5's app.js posts with",
         %{user: user} do
      Seeds.import!(%{id: 710_161, user_id: user.id})
      session = RailsUser.session(user.id)

      doc =
        build_conn()
        |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
        |> get("/imports")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert count(
               doc,
               ~s(form[action="/imports/710161"][method="post"] button[data-testid="import-delete"])
             ) == 1

      assert count(doc, ~s(meta[name="csrf-param"][content="authenticity_token"])) == 1

      [token] =
        doc |> LazyHTML.query(~s(meta[name="csrf-token"])) |> LazyHTML.attribute("content")

      assert RailsCsrf.valid?(session, token)
    end
  end
end
