defmodule Dawarich.Geocoding.Result do
  @moduledoc false

  def city(provider, data) when provider in [:photon, :geoapify], do: props(data)["city"]
  def city(_provider, data), do: first_present_key(address(data), ~w(city town village hamlet))

  def country(provider, data) when provider in [:photon, :geoapify], do: props(data)["country"]
  def country(_provider, data), do: address(data)["country"]

  def country_code(:photon, data), do: props(data)["countrycode"]

  def country_code(:geoapify, data),
    do: if(code = props(data)["country_code"], do: String.upcase(code))

  def country_code(_provider, data), do: address(data)["country_code"]

  defp props(%{"properties" => %{} = p}), do: p
  defp props(_data), do: %{}

  defp address(%{"address" => %{} = a}), do: a
  defp address(_data), do: %{}

  defp first_present_key(address, keys),
    do:
      Enum.find_value(keys, fn key -> if Map.has_key?(address, key), do: {address[key]} end)
      |> then(&(&1 && elem(&1, 0)))
end
