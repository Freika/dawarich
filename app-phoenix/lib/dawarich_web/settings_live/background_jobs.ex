defmodule DawarichWeb.SettingsLive.BackgroundJobs do
  @moduledoc false
  use DawarichWeb, :live_view
  import DawarichWeb.ListParts, only: [page_header: 1]
  alias Dawarich.Admin.BackgroundPage
  alias DawarichWeb.SettingsParts
  embed_templates "background_jobs/*"

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, page(socket.assigns))}

  def page(context) do
    %{
      page_title: label(context.locale, "background_jobs"),
      rails_js: true,
      data: BackgroundPage.read(context.current_user),
      two_factor: Map.get_lazy(context, :two_factor, &SettingsParts.two_factor_available?/0)
    }
  end

  @impl true
  def render(assigns), do: index(assigns)
  defp label(locale, key), do: t(locale, "settings.background_jobs.index." <> key, %{})
end
