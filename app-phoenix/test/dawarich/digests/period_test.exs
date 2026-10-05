defmodule Dawarich.Digests.PeriodTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.DigestFixtures
  alias Dawarich.Digests.{Context, Period}

  test "monthly bounds use the user zone while yearly bounds use the supplied ambient zone" do
    kase = DigestFixtures.case!("southern_yearly")
    DigestFixtures.load!(ScratchRepo, kase)
    context = Context.load!(ScratchRepo, 14101, DigestFixtures.options(kase))
    month = Period.monthly(ScratchRepo, context, "2025suffix", "3suffix")
    year = Period.yearly(ScratchRepo, context, 2025)

    assert context.raw_zone == "Australia/Sydney"
    assert context.user_zone == "Australia/Sydney"
    assert context.time_of_day_zone == "Australia/Sydney"
    assert context.ambient_zone == "Europe/Berlin"
    assert month.zone == "Australia/Sydney"
    assert month.first == DateTime.to_unix(~U[2025-02-28 13:00:00Z])
    assert month.last == DateTime.to_unix(~U[2025-03-31 12:59:59Z])
    assert month.until == ~N[2025-03-31 12:59:59.999999]
    assert year.zone == "Europe/Berlin"
    assert year.first == DateTime.to_unix(~U[2024-12-31 23:00:00Z])
    assert year.last == DateTime.to_unix(~U[2025-12-31 22:59:59Z])
    assert year.until == ~N[2025-12-31 22:59:59.999999]

    for {id, raw} <- [{14998, "Unknown/Zone"}, {14999, ""}] do
      row = hd(kase["input"]["users"])

      DigestFixtures.row!(ScratchRepo, "users", %{
        row
        | "id" => id,
          "email" => "zone-#{id}@example.invalid",
          "settings" => %{"timezone" => raw}
      })

      bad = Context.load!(ScratchRepo, id, DigestFixtures.options(kase))
      assert bad.time_of_day_zone == "Etc/UTC"

      assert_raise ArgumentError, "Invalid Timezone: #{raw}", fn ->
        Period.monthly(ScratchRepo, bad, 2025, 3)
      end

      assert Period.yearly(ScratchRepo, bad, 2025).zone == "Europe/Berlin"
    end
  end

  test "Lite cutoff is one calendar year ago and inherited family access removes it" do
    kase = DigestFixtures.case!("lite_partial_yearly")
    DigestFixtures.load!(ScratchRepo, kase)
    options = Keyword.put(DigestFixtures.options(kase), :now, ~U[2024-02-29 12:00:00Z])
    lite = Context.load!(ScratchRepo, 14101, options)
    assert lite.restricted?
    assert DateTime.compare(lite.cutoff, ~U[2023-02-28 12:00:00Z]) == :eq
    assert lite.stat_cutoff == {2023, 2}
    assert lite.point_cutoff == DateTime.to_unix(lite.cutoff)

    inherited = DigestFixtures.case!("lite_inherited_yearly")

    for table <- ~w(families family_memberships),
        row <- inherited["input"][table],
        do: DigestFixtures.row!(ScratchRepo, table, row)

    family = Context.load!(ScratchRepo, 14101, options)
    refute family.restricted?
    assert family.cutoff == nil
    assert family.stat_cutoff == nil
    assert family.point_cutoff == nil
    assert Context.load!(ScratchRepo, 14102, options).restricted? == false
  end
end
