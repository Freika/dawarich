defmodule Dawarich.Families.Sharing do
  @moduledoc false

  @blank ~r/\A[ \t\n\v\f\r]*\z/
  @iso ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})\z/

  def enabled?(%{} = settings, now) do
    case settings["family"] do
      nil -> false
      %{} = family -> active?(family["location_sharing"], now)
      _other -> raise ArgumentError, "family settings are not an object"
    end
  end

  def enabled?(_settings, _now), do: raise(ArgumentError, "settings are not an object")

  defp active?(%{"enabled" => true} = sharing, now), do: unexpired?(sharing["expires_at"], now)
  defp active?(_sharing, _now), do: false

  defp unexpired?(blank, _now) when blank in [nil, false, [], %{}], do: true

  defp unexpired?(text, now) when is_binary(text) do
    cond do
      text =~ @blank -> true
      text =~ @iso -> text |> DateTime.from_iso8601() |> future?(now)
      true -> raise ArgumentError, "sharing expiry is not ISO 8601 with an offset"
    end
  end

  defp unexpired?(_other, _now), do: raise(ArgumentError, "sharing expiry is not a string")

  defp future?({:ok, at, _offset}, now), do: DateTime.compare(at, now) == :gt
  defp future?(_error, _now), do: raise(ArgumentError, "sharing expiry is not a valid time")
end
