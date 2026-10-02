defmodule DawarichWeb.PlaceDrawerFrameTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias DawarichWeb.PlaceDrawerFrame

  @visits [
    %{
      name: "Frühstück",
      duration: 45,
      started: ~N[2026-03-28 08:15:00],
      ended: ~N[2026-03-28 09:00:00]
    },
    %{
      name: "Mittag",
      duration: 135,
      started: ~N[2026-03-30 09:15:00],
      ended: ~N[2026-03-30 11:30:00]
    },
    %{
      name: "Drei",
      duration: 30,
      started: ~N[2026-04-01 12:00:00],
      ended: ~N[2026-04-01 12:30:00]
    },
    %{
      name: "Vier",
      duration: 30,
      started: ~N[2026-04-02 12:00:00],
      ended: ~N[2026-04-02 12:30:00]
    },
    %{
      name: "Fünf",
      duration: 30,
      started: ~N[2026-04-03 12:00:00],
      ended: ~N[2026-04-03 12:30:00]
    }
  ]

  @full %{
    id: 840_101,
    name: "Café <b>",
    note: "\nErste Zeile",
    city: "Leipzig",
    country: "Germany",
    source: "photon",
    locked: true,
    visit_count: 6,
    total_minutes: 300,
    tags: [
      %{name: "Coffee", icon: "☕", color: "#aa33cc"},
      %{name: "Work", icon: nil, color: nil},
      %{name: "Spät", icon: "", color: "  "}
    ],
    visits: @visits
  }

  @empty %{
    @full
    | note: nil,
      city: nil,
      country: " ",
      source: "manual",
      locked: false,
      visit_count: 0,
      total_minutes: 0,
      tags: [],
      visits: []
  }

  defp render(drawer),
    do: rendered_to_string(PlaceDrawerFrame.frame(%{drawer: drawer, locale: "en", csrf: "TOKEN"}))

  defp tree(html), do: LazyHTML.from_fragment(html)
  defp query(html, selector), do: html |> tree() |> LazyHTML.query(selector)
  defp text(html, selector), do: html |> query(selector) |> LazyHTML.text() |> squish()
  defp attr(html, selector, name), do: html |> query(selector) |> LazyHTML.attribute(name)
  defp squish(text), do: text |> String.replace(~r/\s+/, " ") |> String.trim()

  test "the full drawer" do
    html = render(@full)

    assert html =~ ~r{\A<turbo-frame id="place-drawer">}
    assert attr(html, ".place-drawer.place-drawer--open", "data-place-id") == ["840101"]
    assert text(html, ".place-drawer__icon span.text-2xl.leading-none") == "☕"

    assert attr(html, ".place-drawer__name-lock", "title") == [
             ~s(You named this place, so automatic naming will not change it. Rename it to "Suggested place" to hand it back to automatic naming.)
           ]

    assert attr(html, ".place-drawer__name-lock", "data-testid") == ["place-name-lock"]
    assert html =~ "Café &lt;b&gt;"
    assert text(html, ".place-drawer__location") == "Leipzig, Germany"
    assert text(html, ".place-drawer__source") == "Source: Photon"

    assert html |> query(".place-drawer__stat-value") |> Enum.map(&squish(LazyHTML.text(&1))) ==
             ["6", "5.0", "0h 50m"]

    assert text(html, ".place-drawer__stat:first-child .place-drawer__stat-label") == "6 visits"

    assert attr(html, ".place-drawer__tag-chip", "style") == [
             "background-color: #aa33cc;",
             "",
             ""
           ]

    assert html |> query(".place-drawer__visit-time") |> Enum.map(&squish(LazyHTML.text(&1))) == [
             "08:15 → 09:00 on 2026-03-28",
             "09:15 → 11:30 on 2026-03-30",
             "12:00 → 12:30 on 2026-04-01",
             "12:00 → 12:30 on 2026-04-02",
             "12:00 → 12:30 on 2026-04-03"
           ]

    assert html
           |> query(".place-drawer__visit-duration")
           |> Enum.map(&LazyHTML.text/1)
           |> Enum.take(2) ==
             ["0h 45m", "2h 15m"]
  end

  test "the note textarea keeps Rails' leading newline" do
    assert render(@full) =~ ~s(name="place[note]">\n\nErste Zeile</textarea>)
    assert render(@empty) =~ ~s(name="place[note]">\n</textarea>)
  end

  test "Rails' form helpers, verbatim" do
    html = Regex.replace(~r/>\s+</, render(@full), "><")

    assert html =~
             ~s(<form data-turbo-frame="place-drawer" action="/places/840101" accept-charset="UTF-8" method="post"><input type="hidden" name="_method" value="patch"><input type="hidden" name="authenticity_token" value="TOKEN">)

    assert html =~
             ~s(<label for="place-drawer-note" class="place-drawer__notes-label">Notes</label>)

    assert html =~
             ~s(<textarea id="place-drawer-note" rows="3" class="place-drawer__notes-input" name="place[note]">)

    assert html =~
             ~s(<input type="submit" name="commit" value="Save" class="place-drawer__notes-submit" data-disable-with="Save">)

    assert html =~
             ~s(<form data-action="turbo:submit-end->place-detail#deleted" data-place-detail-id-param="840101" class="button_to" method="post" action="/places/840101"><input type="hidden" name="_method" value="delete"><button class="place-drawer__action place-drawer__action--delete" data-turbo-confirm="Delete this place? This cannot be undone." type="submit">Delete</button><input type="hidden" name="authenticity_token" value="TOKEN"></form>)

    assert html =~
             ~s(<button type="button" class="place-drawer__action place-drawer__action--edit" data-action="maps--maplibre#handleEdit" data-id="840101" data-entity-type="place">Edit</button>)

    assert html =~
             ~s(<button type="button" class="place-drawer__action place-drawer__action--merge" disabled>Merge</button>)

    assert html =~
             ~s(<button type="button" class="btn btn-ghost btn-sm btn-circle" aria-label="Close" data-action="place-detail#close">✕</button>)
  end

  test "rounding and averages follow Ruby" do
    stats = fn drawer ->
      drawer
      |> render()
      |> query(".place-drawer__stat-value")
      |> Enum.map(&squish(LazyHTML.text(&1)))
    end

    assert stats.(%{@empty | visit_count: 2, total_minutes: 9}) == ["2", "0.2", "0h 4m"]
    assert stats.(@empty) == ["0", "0.0", "0h 0m"]
    assert stats.(%{@empty | visit_count: 1, total_minutes: 61}) == ["1", "1.0", "1h 1m"]
    assert stats.(%{@empty | visit_count: 3, total_minutes: 200}) == ["3", "3.3", "1h 6m"]
  end

  test "the empty drawer" do
    html = render(@empty)

    assert query(html, ".place-drawer__icon svg.w-6.h-6") |> Enum.count() == 1
    refute html =~ "text-2xl leading-none"
    assert query(html, ".place-drawer__location") |> Enum.count() == 0
    assert query(html, ".place-drawer__name-lock") |> Enum.count() == 0
    assert text(html, ".place-drawer__tags-empty") == "No tags"
    assert query(html, ".place-drawer__tag-list") |> Enum.count() == 0
    assert text(html, ".place-drawer__visits-empty") == "No visits yet"
    assert query(html, ".place-drawer__visits-list") |> Enum.count() == 0
    assert text(html, ".place-drawer__source") == "Source: Manual"
    assert text(html, ".place-drawer__stat:first-child .place-drawer__stat-label") == "0 visits"
  end

  test "inline siblings keep their whitespace" do
    html = render(@full)

    assert html =~ ~r{stat-value">6</span>\s+<span class="place-drawer__stat-label">}
    assert html =~ ~r{stat-value">5\.0</span>\s+<span class="place-drawer__stat-label">}
    assert html =~ ~r{class="place-drawer__visit-time">08:15 → 09:00 on 2026-03-28</span>}
    assert html =~ ~r{<p class="place-drawer__source">Source: Photon</p>}
  end
end
