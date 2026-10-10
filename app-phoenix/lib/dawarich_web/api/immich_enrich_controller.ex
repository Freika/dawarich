defmodule DawarichWeb.Api.ImmichEnrichController do
  @moduledoc false
  @behaviour Plug
  defdelegate init(action), to: DawarichWeb.Api.ImmichController
  defdelegate call(conn, action), to: DawarichWeb.Api.ImmichController
end
