defmodule DawarichWeb.ExportsLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Dawarich.Test.RailsUser
  alias Dawarich.Test.ImportsExportsSeeds, as: Seeds
  alias DawarichWeb.BlobPath

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})

    user =
      RailsUser.insert!(%{
        id: 7201,
        email: "a7-exports-live@dawarich.test",
        settings: %{"timezone" => "Europe/Berlin"}
      })

    %{user: user}
  end

  defp live_as(user, path \\ "/exports"),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

  describe "route" do
    test "a signed-in user gets the page under Rails' title", %{user: user} do
      {:ok, _view, html} = live_as(user)
      assert html =~ ">Exports | Dawarich</title>"
    end

    test "a signed-out visitor is sent to Rails' sign-in page" do
      assert redirected_to(get(build_conn(), "/exports?page=2"), 302) ==
               "http://www.example.com/users/sign_in"
    end

    test "HEAD answers without a body", %{user: user} do
      conn = head(RailsUser.signed_in(user.id), "/exports")
      assert {conn.status, conn.resp_body} == {200, ""}
    end
  end

  defp content(html),
    do: html |> LazyHTML.from_document() |> LazyHTML.query("div.px-4.flex-1 div.w-full.my-5")

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  defp at(hours_ago), do: NaiveDateTime.add(NaiveDateTime.utc_now(), -hours_ago * 3600)

  describe "list" do
    test "an empty list links to Rails' points page with the absolute URL Rails renders", %{
      user: user
    } do
      {:ok, _view, html} = live_as(user)
      page = content(html)

      assert html =~ "No exports yet"

      assert count(page, ~s(#exports a.link.link-primary[href="http://www.example.com/points"])) ==
               1

      assert count(page, ~s(#exports a.btn.btn-primary[href="http://www.example.com/points"])) ==
               1

      assert count(page, "#exports table") == 0
    end

    test "a completed export with a file downloads from Rails' signed blob path under the export's name",
         %{user: user} do
      name = "export_from_2024-03-01_to_2024-03-31.json"
      Seeds.export!(%{id: 720_101, user_id: user.id, name: name, created_at: at(1)})
      Seeds.file!("Export", 720_101, "file", 972_101, 2_048_000, name <> ".zip")

      {:ok, _view, html} = live_as(user)
      path = BlobPath.redirect_path(972_101, name <> ".zip")

      assert count(
               content(html),
               ~s(#export_720101 a.btn.btn-ghost.btn-xs[href="#{path}"][download="#{name}"])
             ) == 1
    end

    test "the download link follows Rails: a legacy URL; nothing for a blank URL, no file, or before completion",
         %{user: user} do
      Seeds.export!(%{
        id: 720_111,
        user_id: user.id,
        url: "exports/legacy.gpx",
        name: "legacy.gpx",
        created_at: at(1)
      })

      Seeds.export!(%{id: 720_112, user_id: user.id, url: "  ", created_at: at(2)})
      Seeds.export!(%{id: 720_113, user_id: user.id, created_at: at(3)})
      Seeds.export!(%{id: 720_114, user_id: user.id, status: 1, created_at: at(4)})
      Seeds.file!("Export", 720_114, "file", 972_114, 42, "early.json.zip")

      {:ok, _view, html} = live_as(user)
      page = content(html)

      assert count(page, ~s(#export_720111 a[href="exports/legacy.gpx"][download="legacy.gpx"])) ==
               1

      for id <- [720_112, 720_113, 720_114],
          do: assert(count(page, "#export_#{id} a[download]") == 0, "export #{id}")
    end

    test "deleting goes through Rails' method link, never a LiveView event", %{user: user} do
      Seeds.export!(%{id: 720_121, user_id: user.id})
      {:ok, _view, html} = live_as(user)
      page = content(html)

      assert count(
               page,
               ~s(#export_720121 a[href="/exports/720121"][data-turbo-method="delete"][data-turbo-confirm="Are you sure?"])
             ) == 1

      assert count(page, "[phx-click], [phx-submit], form") == 0
    end

    test "lists only the signed-in user's exports", %{user: user} do
      other = Seeds.user!(7202, %{})
      Seeds.export!(%{id: 720_131, user_id: user.id})
      Seeds.export!(%{id: 720_231, user_id: other.id})

      {:ok, _view, html} = live_as(user)

      assert content(html) |> LazyHTML.query("#exports tbody tr") |> LazyHTML.attribute("id") ==
               ["export_720131"]
    end

    test "the file size header is Rails' literal and links the size sort", %{user: user} do
      Seeds.export!(%{id: 720_141, user_id: user.id})
      {:ok, _view, html} = live_as(user)

      assert content(html)
             |> LazyHTML.query(~s(th a[href="/exports?order_by=asc&sort_by=byte_size"]))
             |> LazyHTML.text()
             |> String.trim() == "File size"
    end

    test "a failed export shows its error in a tooltip", %{user: user} do
      Seeds.export!(%{id: 720_151, user_id: user.id, status: 3, error_message: "Timeout <x>"})
      {:ok, _view, html} = live_as(user)

      assert content(html)
             |> LazyHTML.query("#export_720151 .cursor-help")
             |> LazyHTML.attribute("data-tip") ==
               ["Timeout <x>"]
    end
  end

  describe "head" do
    test "Turbo's morph metas come with the notifications and imports pages but not the exports page, as Rails' controllers decide",
         %{user: user} do
      now = NaiveDateTime.utc_now()

      Dawarich.Repo.insert_all("notifications", [
        %{
          id: 720_199,
          user_id: user.id,
          title: "x",
          content: "x",
          kind: 0,
          created_at: now,
          updated_at: now
        }
      ])

      refute html_response(get(RailsUser.signed_in(user.id), "/exports"), 200) =~
               "turbo-refresh-method"

      for path <- ["/notifications", "/notifications/720199", "/imports"] do
        html = html_response(get(RailsUser.signed_in(user.id), path), 200)
        assert html =~ ~s(name="turbo-refresh-method"), path
        assert html =~ ~s(name="turbo-refresh-scroll"), path
      end
    end
  end
end
