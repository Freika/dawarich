defmodule DawarichWeb.StorageGate do
  @moduledoc false

  def native?(_conn, _params),
    do: "active_storage" not in Application.get_env(:dawarich, :rails_routes, [])
end
