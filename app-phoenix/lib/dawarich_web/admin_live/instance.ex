defmodule DawarichWeb.AdminLive.Instance do
  @moduledoc false
  use DawarichWeb, :live_view

  alias Dawarich.Admin.{InstancePage, JobHealth}
  alias DawarichWeb.{AdminInstance, SettingsParts}

  @impl true
  def mount(params, _session, socket) do
    case page(params, socket.assigns) do
      {:ok, page} -> {:ok, assign(socket, page)}
      :rails -> {:ok, redirect(socket, to: DawarichWeb.AdminLiveAuth.request_url(socket))}
    end
  end

  def page(params, context) do
    repo = Map.get(context, :repo, Dawarich.Repo)

    with {:ok, data} <- InstancePage.load(repo, Map.get(context, :env, System.get_env())) do
      health =
        Map.get_lazy(context, :health, fn ->
          JobHealth.load(repo, Dawarich.Jobs.repo(), System.get_env("DAWARICH_PHOENIX_NODE"))
        end)

      health =
        if Map.has_key?(health, "summary"),
          do: %{summary: health["summary"], gauges: health["gauges"]},
          else: health

      {:ok,
       %{
         page_title: t(context.locale, "admin.settings.show.title", %{}),
         rails_js: true,
         data: data,
         section: InstancePage.section(data, params["section"]),
         health: health,
         two_factor: Map.get_lazy(context, :two_factor, &SettingsParts.two_factor_available?/0)
       }}
    end
  end

  @impl true
  def render(assigns), do: AdminInstance.show(assigns)
end
