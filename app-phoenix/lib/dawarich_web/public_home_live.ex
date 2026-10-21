defmodule DawarichWeb.PublicHomeLive do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Dawarich.Auth.RegistrationSetting

  def registration(false), do: {:ok, true}
  def registration(true), do: RegistrationSetting.fetch()
  def mount(_params, _session, socket), do: {:ok, redirect(socket, to: "/")}
  def render(assigns), do: ~H""
end
