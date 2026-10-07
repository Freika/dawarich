defmodule DawarichWeb.StandaloneSettings do
  @moduledoc false
  @behaviour Plug
  def enabled?(_conn, _params), do: Dawarich.Standalone.enabled?()
  def init(opts), do: opts
  def call(conn, _opts), do: DawarichWeb.SettingsActions.call(conn, :update)
end
