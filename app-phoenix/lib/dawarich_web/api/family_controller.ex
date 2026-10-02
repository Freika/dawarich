defmodule DawarichWeb.Api.FamilyController do
  @moduledoc false
  @behaviour Plug

  alias Dawarich.Families.Locations
  alias DawarichWeb.Api.{Body, Respond}

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, :locations) do
    case Locations.read(conn.assigns.api_user, DateTime.utc_now()) do
      {:ok, status, term} -> Respond.json(conn, status, term)
      {:replay, reason} -> Body.replay(conn, reason)
    end
  rescue
    error -> Body.replay(conn, inspect(error.__struct__))
  end
end
