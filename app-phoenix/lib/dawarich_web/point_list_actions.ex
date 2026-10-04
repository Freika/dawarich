defmodule DawarichWeb.PointListActions do
  @moduledoc false
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts), do: DawarichWeb.Api.Body.replay(conn, "point list write action")
end
