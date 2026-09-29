defmodule DawarichWeb.ImportsLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, :page_title, t(socket.assigns.locale, "imports.index.imports", %{}))}

  @impl true
  def render(assigns), do: ~H|<div class="w-full my-5"></div>|
end
