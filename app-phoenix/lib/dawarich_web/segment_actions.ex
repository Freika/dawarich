defmodule DawarichWeb.SegmentActions do
  @moduledoc false
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts), do: DawarichWeb.Api.Body.replay(conn, "segment write action")
end
