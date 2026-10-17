defmodule Dawarich.Geocoding.CountriesTest do
  use Dawarich.GeocodingCase, async: false

  alias Dawarich.Geocoding.Countries

  @aliases_rb Path.expand("../../../../app/services/countries/name_aliases.rb", __DIR__)

  test "aliases are Rails'" do
    [open | lines] = @aliases_rb |> File.read!() |> String.split("\n") |> Enum.slice(12..32)
    {entries, [close]} = Enum.split(lines, -1)
    assert String.trim(open) == "ALIASES = {"
    assert String.trim(close) == "}.freeze"

    rails =
      for line <- entries, into: %{} do
        [_, _, from, _, to] = Regex.run(~r/^\s*(['"])(.+?)\1 => (['"])(.+?)\3,?$/u, line)
        {from, to}
      end

    assert map_size(rails) == 19
    assert Countries.aliases() == rails
  end

  test "name, then code; a code mismatch drops the name match" do
    f = load!("country_alias_and_mismatch")

    for {result, point} <- Enum.zip(f["results"], f["expected"]["points"]) do
      props = result["data"]["properties"]
      found = Countries.find(ScratchRepo, props["country"], props["countrycode"])
      assert {props["country"], found && found.id} == {props["country"], point["country_id"]}
    end

    assert %{id: 35, iso_a2: "US"} = Countries.find(ScratchRepo, "Nowhere", "us")
    assert %{id: 35} = Countries.find(ScratchRepo, "United States", nil)
    assert %{id: 35} = Countries.find(ScratchRepo, "", "US")
    assert Countries.find(ScratchRepo, nil, "") == nil
  end
end
