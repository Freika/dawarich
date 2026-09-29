defmodule DawarichWeb.Slices do
  @moduledoc false

  def owned?(slice) do
    DawarichWeb.LayoutAssigns.self_hosted?(%{"SELF_HOSTED" => System.get_env("SELF_HOSTED")}) and
      Atom.to_string(slice) not in rails_slices(System.get_env("DAWARICH_RAILS_SLICES", ""))
  end

  defp rails_slices(value),
    do: value |> String.split(",") |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
end
