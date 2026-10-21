defmodule Dawarich.EnhancedImport.GpxPlace do
  @moduledoc false

  alias Dawarich.{Geo, ReleaseMigration, RubyDecimal}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def build(attrs, fields) do
    with lat when is_float(lat) <- coordinate(attrs["lat"]),
         lon when is_float(lon) <- coordinate(attrs["lon"]),
         false <- Geo.distance_m({lat, lon}, {0.0, 0.0}) <= 5000 do
      category = presence(fields["type"])

      %{
        external_place_id: identity(fields["name"], lat, lon),
        name: presence(fields["name"]),
        latitude: lat,
        longitude: lon,
        semantic_type: category,
        tag_name: category,
        tag_color: color(fields["color"])
      }
    else
      _ -> nil
    end
  end

  defp coordinate(value), do: if(Ruby.blank?(value), do: nil, else: Ruby.float(value))

  defp identity(name, lat, lon) do
    name = String.downcase(ReleaseMigration.ruby_strip(name || ""))
    seed = "#{name}|#{RubyDecimal.fixed(lat, 5)}|#{RubyDecimal.fixed(lon, 5)}"
    "gpx:" <> binary_part(Base.encode16(:crypto.hash(:sha, seed), case: :lower), 0, 32)
  end

  defp color(value) do
    hex =
      if Ruby.present?(value),
        do:
          value
          |> ReleaseMigration.ruby_strip()
          |> String.replace_prefix("#", "")
          |> String.downcase()

    cond do
      hex == nil or not (hex =~ ~r/\A[0-9a-f]+\z/) -> nil
      byte_size(hex) == 3 -> "#" <> for(<<c <- hex>>, into: "", do: <<c, c>>)
      byte_size(hex) == 6 -> "#" <> hex
      byte_size(hex) == 8 -> "#" <> binary_part(hex, 2, 6)
      true -> nil
    end
  end

  defp presence(value), do: if(Ruby.present?(value), do: value)
end
