defmodule DawarichWeb.Api.LocationsController do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.Locations.{Closure, Suggestions}
  alias DawarichWeb.Api.Respond

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, action) do
    {:ok, status, term} =
      case action do
        :index -> Closure.read(conn.assigns.api_user, conn.assigns.api_params)
        :suggestions -> Suggestions.run(conn.assigns.api_user, conn.assigns.api_params)
      end

    Respond.json(conn, status, term)
  end
end
