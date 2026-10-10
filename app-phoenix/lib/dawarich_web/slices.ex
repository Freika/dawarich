defmodule DawarichWeb.Slices do
  @moduledoc false

  @api_slices ~w(ingest api_foundation api_map_reads api_stats api_places api_locations_photos api_family api_shared api_notes api_visits api_account)a

  def head?(slice), do: slice in @api_slices or slice == :cable

  def owned?(slice, native_api \\ false) do
    Dawarich.Standalone.enabled?() or
      ((native_api or slice == :cable or
          DawarichWeb.LayoutAssigns.self_hosted?(%{
            "SELF_HOSTED" => System.get_env("SELF_HOSTED")
          })) and
         Atom.to_string(slice) not in rails_slices(System.get_env("DAWARICH_RAILS_SLICES", "")))
  end

  defp rails_slices(value),
    do: value |> String.split(",") |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
end
