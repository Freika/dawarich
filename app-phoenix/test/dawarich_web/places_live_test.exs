defmodule DawarichWeb.PlacesLiveTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Dawarich.Test.FrameSeeds, as: S
  alias Dawarich.Test.RailsUser

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    %{user: user!(8431)}
  end

  defp user!(id, settings \\ %{"timezone" => "Europe/Berlin"}),
    do: S.user!(id, settings, %{email: "a84-#{id}@example.invalid", api_key: "a84-k-#{id}"})

  defp live_as(user, path),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

  defp fill!(user, count),
    do: for(n <- 1..count, do: S.place!(user.id, 843_100 + n, "Ort #{n}"))

  defp hrefs(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.attribute("href")

  test "Rails' title, tabs and table for page 1; HEAD without a body", %{user: user} do
    fill!(user, 23)
    {:ok, view, html} = live_as(user, "/places")

    assert html =~ ">Places | Dawarich</title>"

    assert hrefs(html, "[role='tab']") == [
             "/map/v2?panel=timeline&date=today&status=confirmed",
             "/places"
           ]

    assert has_element?(view, "a[role='tab'].tab-active[href='/places']")
    refute has_element?(view, "a[role='tab'].tab-active[href^='/map']")

    assert html |> LazyHTML.from_fragment() |> LazyHTML.query("#places tbody tr") |> Enum.count() ==
             20

    assert html
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("[aria-label='pager']")
           |> Enum.count() == 1

    conn = head(RailsUser.signed_in(user.id), "/places")
    assert {conn.status, conn.resp_body} == {200, ""}
  end

  test "the empty hero for no places and for an out-of-range page", %{user: user} do
    {:ok, view, html} = live_as(user, "/places")
    assert html =~ "Hello there!"
    assert html =~ "Here you&#39;ll find your places"
    refute has_element?(view, "#places table")
    refute has_element?(view, "[aria-label='pager']")

    fill!(user, 23)
    {:ok, far, html} = live_as(user, "/places?page=3")
    assert html =~ "Hello there!"
    refute has_element?(far, "#places table")
    refute has_element?(far, "[aria-label='pager']")
  end

  test "the delete link carries the raw page value", %{user: user} do
    fill!(user, 23)

    for {path, query} <- [
          {"/places", ""},
          {"/places?page=2abc", "?page=2abc"},
          {"/places?page=2+x", "?page=2+x"},
          {"/places?page=", "?page="}
        ] do
      {:ok, _view, html} = live_as(user, path)
      [first | _] = hrefs(html, "#places a[data-turbo-method='delete']")
      assert first =~ ~r{\A/places/\d+#{Regex.escape(query)}\z}
    end
  end

  test "the paginator patches and keeps other query keys", %{user: user} do
    fill!(user, 23)
    {:ok, view, html} = live_as(user, "/places?view=table")
    assert html =~ "Ort 1<"

    html = view |> element("[aria-label='pager'] a", "2") |> render_click()

    assert_patch(view, "/places?page=2&view=table")
    assert html =~ "Ort 21<"
    refute html =~ "Ort 1<"
  end

  test "a state the gate would refuse redirects to the same URL" do
    mars = user!(8432, %{"timezone" => "Mars/Phobos"})
    {:ok, view, html} = live_as(mars, "/places")
    assert html =~ "Hello there!"

    S.place!(mars.id, 843_201, "Neu")

    assert {:error, {:redirect, %{to: "/places?view=x"}}} = render_patch(view, "/places?view=x")
  end

  test "signed-out visitors get Rails' sign-in redirect" do
    assert redirected_to(get(build_conn(), "/places"), 302) ==
             "http://www.example.com/users/sign_in"
  end
end
