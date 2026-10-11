defmodule DawarichWeb.FamiliesLive.Form do
  @moduledoc false
  use DawarichWeb, :live_view
  alias DawarichWeb.FamilyNativeLive
  @impl true
  def mount(_, _, socket), do: {:ok, FamilyNativeLive.mount(socket)}
  @impl true
  def handle_event(event, params, socket), do: FamilyNativeLive.event(event, params, socket)
  @impl true
  def handle_info(_, socket), do: {:noreply, socket}
  @impl true
  def handle_params(_, _, socket), do: {:noreply, socket}
  @impl true
  def render(assigns), do: DawarichWeb.FamilyNativeForms.native_form(assigns)
end
