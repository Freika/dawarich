defmodule DawarichWeb.LiveSocket do
  @moduledoc false
  use Phoenix.Socket

  channel "lvu:*", Phoenix.LiveView.UploadChannel
  channel "lv:*", DawarichWeb.AuthorizedLiveChannel

  defdelegate connect(params, socket, connect_info), to: Phoenix.LiveView.Socket
  defdelegate id(socket), to: Phoenix.LiveView.Socket
end
