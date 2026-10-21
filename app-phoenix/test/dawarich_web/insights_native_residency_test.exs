defmodule DawarichWeb.InsightsNativeResidencyTest do
  use Dawarich.DataCase, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.FrameSeeds

  test "native residency retains calendar days percentages and consecutive periods" do
    user = FrameSeeds.user!(8997, %{"timezone" => "UTC"})
    first = DateTime.to_unix(~U[2024-03-01 12:00:00Z])

    for n <- 0..1,
        do: FrameSeeds.point!(user.id, 89970 + n, first + n * 86400, %{country_name: "Germany"})

    assert {:ok, page} =
             Dawarich.Insights.ResidencyPage.load(Scope.for_user(user, "en"), %{"year" => "2024"},
               now: ~U[2026-10-10 10:00:00Z],
               self_hosted: true
             )

    assert hd(page.countries).year_percentage == 0.5
    assert hd(page.countries).iso == "DE"

    html =
      render_component(&DawarichWeb.InsightsLive.NativeParts.residency/1,
        data: page,
        locale: "en",
        query: %{"year" => "2024"},
        path: "/insights"
      )

    doc = LazyHTML.from_document(html)
    assert Enum.count(LazyHTML.query(doc, "[data-date]")) == 366

    assert LazyHTML.attribute(
             LazyHTML.query(doc, "[data-date='2024-03-01']"),
             "aria-label"
           )
           |> hd() =~ "Germany"

    assert page.total == 2
    assert has_country_calendar?(doc)
    assert html =~ "2 days"
    refute html =~ "turbo-frame"
  end

  defp has_country_calendar?(doc),
    do:
      Enum.count(LazyHTML.query(doc, ".year-calendar[data-mode=both] [data-country=Germany]")) ==
        2
end
