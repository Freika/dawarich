defmodule DawarichWeb.SettingsLive.UserShow do
  @moduledoc false
  use DawarichWeb, :live_view
  import DawarichWeb.HumanDatetime, only: [human_datetime: 1]
  import DawarichWeb.Icon, only: [icon: 1]
  alias Dawarich.Admin.UsersPage
  alias DawarichWeb.{NumberFormat, SettingsParts}
  embed_templates "user_show/*"

  @impl true
  def mount(params, _session, socket) do
    case page(params, socket.assigns) do
      {:ok, page} -> {:ok, assign(socket, page)}
      :rails -> {:ok, redirect(socket, to: DawarichWeb.AdminLiveAuth.request_url(socket))}
    end
  end

  def page(%{"id" => id}, context) do
    with {id, ""} <- Integer.parse(id),
         {:ok, target} <- UsersPage.find(context.current_user, id, :show) do
      {:ok,
       %{
         page_title: t(context.locale, "settings.users.show.user_email", %{email: target.email}),
         rails_js: true,
         target: target,
         two_factor: Map.get_lazy(context, :two_factor, &SettingsParts.two_factor_available?/0)
       }}
    else
      _ -> :rails
    end
  end

  @impl true
  def render(assigns), do: show(assigns)
  defp label(locale, key), do: t(locale, "settings.users.show." <> key, %{})
  defp status(0), do: {"inactive", "error"}
  defp status(1), do: {"active", "success"}
  defp status(2), do: {"trial", "warning"}
end
