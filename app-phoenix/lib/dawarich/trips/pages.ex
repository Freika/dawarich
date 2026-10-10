defmodule Dawarich.Trips.Pages do
  @moduledoc false

  alias Dawarich.{RubyInteger, TripSettings}
  alias Dawarich.Accounts.Scope
  alias Dawarich.SharedLinks.FamilyAudience
  alias Dawarich.Trips.{DayWindow, DetailProjection, ListProjection}

  @max_page 1_000_000_000_000

  def normalize(params) when is_map(params),
    do: %{page: page(params["page"]), family_page: page(params["family_page"])}

  def normalize(_params), do: normalize(%{})

  def list(%Scope{user: user}, params, now) do
    query = normalize(params)

    with {:ok, settings} <- settings(user) do
      own = ListProjection.cards(user, query.page)
      family = FamilyAudience.trips(user, query.family_page, now)

      {:ok,
       %{
         query: query,
         entries: own.entries,
         total_pages: own.total_pages,
         family_entries: family.entries,
         family_total_pages: family.total_pages,
         settings: Map.take(settings, [:unit, :factor])
       }}
    end
  end

  def get(%Scope{user: user}, id, now) do
    with {:ok, id} <- id(id),
         {:ok, settings} <- settings(user),
         do: DetailProjection.load(user, id, settings, now)
  end

  def days(%Scope{user: user}, id, from) do
    with {:ok, id} <- id(id),
         {:ok, settings} <- settings(user),
         do: DayWindow.load(user, id, from, settings)
  end

  def id(id) when is_integer(id) and id > 0 and id < 9_223_372_036_854_775_807, do: {:ok, id}

  def id(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} -> id(value)
      _ -> {:error, :not_found}
    end
  end

  def id(_id), do: {:error, :not_found}

  defp page(value) when is_binary(value) or is_nil(value) or is_integer(value),
    do: value |> RubyInteger.to_i() |> max(1) |> min(@max_page)

  defp page(_value), do: 1

  defp settings(user) do
    case TripSettings.read(Dawarich.UserSettings.get(user)) do
      {:ok, settings} -> {:ok, settings}
      _ -> {:error, :unsupported}
    end
  end
end
