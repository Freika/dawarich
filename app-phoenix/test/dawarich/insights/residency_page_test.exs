defmodule Dawarich.Insights.ResidencyPageTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.Accounts.Scope
  alias Dawarich.Insights.ResidencyPage
  alias Dawarich.Test.FrameSeeds
  @now ~U[2026-10-10 10:00:00Z]

  test "native residency preserves owner-local bounds source UTC days ties and full country totals" do
    user = FrameSeeds.user!(8971, %{"timezone" => "Pacific/Kiritimati"})
    foreign = FrameSeeds.user!(8972)
    first = DateTime.to_unix(~U[2024-12-31 11:00:00Z])
    FrameSeeds.point!(user.id, 89711, first, %{country_name: "Germany"})
    FrameSeeds.point!(user.id, 89712, first + 1, %{country_name: "France"})
    FrameSeeds.point!(foreign.id, 89713, first, %{country_name: "Private country"})
    FrameSeeds.point!(user.id, 89714, first - 7200, %{country_name: "Outside year"})

    for n <- 1..61,
        do:
          FrameSeeds.point!(user.id, 89800 + n, first + 86400 + n, %{country_name: "Country #{n}"})

    scope = Scope.for_user(user, "en")

    assert {:ok, page} =
             ResidencyPage.load(scope, %{"year" => "2025"}, now: @now, self_hosted: true)

    assert page.total == 2
    assert length(page.countries) == 50
    assert page.more
    assert hd(page.daily) == [~D[2024-12-31], "France"]
    refute Enum.any?(page.countries, &(&1.name in ["Private country", "Outside year"]))

    assert {:ok, second} =
             ResidencyPage.load(scope, %{"year" => "2025", "residency_page" => "2"},
               now: @now,
               self_hosted: true
             )

    assert length(second.countries) == 13
    assert second.total == 2
    refute second.more

    assert MapSet.disjoint?(
             MapSet.new(page.countries, & &1.name),
             MapSet.new(second.countries, & &1.name)
           )
  end

  test "native residency refuses Lite all-time malformed and replaced identity before point reads" do
    user = FrameSeeds.user!(8973, %{"timezone" => "UTC"}, %{plan: 0})
    scope = Scope.for_user(user, "en")

    for params <- [%{"year" => "all"}, %{"year" => "2025"}] do
      assert {:ok, %{state: :restricted}} =
               ResidencyPage.load(scope, params, now: @now, self_hosted: false)
    end

    assert {:error, :invalid_input} =
             ResidencyPage.load(scope, %{"year" => []}, now: @now, self_hosted: true)

    Dawarich.Repo.query!(
      "UPDATE users SET encrypted_password='replaced-identity-000000000000000000' WHERE id=$1",
      [user.id], log: false)

    assert {:error, :stale_session} =
             ResidencyPage.load(scope, %{"year" => "2025"}, now: @now, self_hosted: true)
  end
end
