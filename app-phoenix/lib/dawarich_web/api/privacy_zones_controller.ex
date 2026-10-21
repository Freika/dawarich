defmodule DawarichWeb.Api.PrivacyZonesController do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.MapApi.PrivacyZones
  alias DawarichWeb.Api.Respond
  def init(action), do: action

  def call(conn, :index),
    do: Respond.json(conn, 200, PrivacyZones.term(PrivacyZones.fetch(conn.assigns.api_user)))
end
