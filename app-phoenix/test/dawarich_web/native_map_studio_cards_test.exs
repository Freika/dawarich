defmodule DawarichWeb.NativeMapStudioCardsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias Dawarich.Test.ParityHTML
  alias DawarichWeb.{MapGalleryCards, RouteVideoCard}

  test "embedded poster cards preserve Rails markup and delete through the native owner" do
    attrs = [
      poster: %{
        id: 42,
        name: "Queued",
        status: 0,
        settings: %{},
        files: %{"image" => nil, "print_pdf" => nil}
      },
      locale: "en"
    ]

    rails = render_component(&MapGalleryCards.poster_card/1, attrs)
    native = render_component(&MapGalleryCards.poster_card/1, attrs ++ [native: true])

    assert native
           |> String.replace(~s(href="#"), ~s(href="/posters/42"))
           |> ParityHTML.normalize() ==
             ParityHTML.normalize(rails)

    doc = LazyHTML.from_fragment(native)

    assert doc
           |> LazyHTML.query("a[phx-click='poster:delete'][href='#']")
           |> Enum.count() == 1

    refute native =~ "data-turbo"
  end

  test "embedded expired video cards preserve Rails markup and restore into the map studio" do
    attrs = [
      video: %{
        id: 52,
        name: "Expired",
        status: 1,
        files: %{"file" => nil},
        shown_at: ~N[2026-10-16 12:00:00],
        settings_json: ~s({"format":"square"})
      },
      locale: "en"
    ]

    rails = render_component(&RouteVideoCard.route_video_card/1, attrs)

    native =
      render_component(&RouteVideoCard.route_video_card/1, attrs ++ [native: true, target: 7])

    assert native
           |> String.replace(~s(href="#"), ~s(href="/route_videos/52"))
           |> ParityHTML.normalize() ==
             ParityHTML.normalize(rails)

    doc = LazyHTML.from_fragment(native)
    [restore] = doc |> LazyHTML.query("button[phx-click]") |> LazyHTML.attribute("phx-click")

    assert [["dispatch", %{"to" => "#video-studio", "detail" => %{"recipe" => _}}]] =
             Jason.decode!(restore)

    assert doc
           |> LazyHTML.query("a[phx-click='video:delete'][phx-target='7'][href='#']")
           |> Enum.count() ==
             1

    refute native =~ "data-action"
    refute native =~ "data-turbo"
  end
end
