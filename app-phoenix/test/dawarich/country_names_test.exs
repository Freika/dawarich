defmodule Dawarich.CountryNamesTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Dawarich.{CountryNames, Repo}
  alias Dawarich.Test.ParityHTML

  @corpus "test/fixtures/stats_corpus.json"
          |> File.read!()
          |> Jason.decode!()
          |> Map.fetch!("countries")

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    stamp = NaiveDateTime.utc_now(:second)

    Repo.insert_all(
      "countries",
      for(
        [name, code] <- @corpus["table"],
        do: %{name: name, iso_a2: code, iso_a3: code, created_at: stamp, updated_at: stamp}
      )
    )

    :ok
  end

  test "normalize/2 and the flags follow StatsHelper#normalize_country_name and CountryFlagHelper#country_flag" do
    table = CountryNames.table()
    assert table == Enum.map(@corpus["table"], &List.to_tuple/1)

    for %{"input" => input, "normalized" => normalized, "flag" => flag} <- @corpus["cases"] do
      assert CountryNames.normalize(input, table) == normalized, inspect(input)
      html = render_component(&DawarichWeb.Icon.country_flag/1, name: input, table: table)
      assert ParityHTML.normalize(html) == ParityHTML.normalize(flag), inspect(input)
    end
  end

  test "standardize/1 is IsoCodeMapper's exact, alias, case-insensitive, then partial match" do
    assert CountryNames.standardize("Czechia") == "Czech Republic"
    assert CountryNames.standardize("germany") == "Germany"
    assert CountryNames.standardize("Atlantis") == nil
  end
end
