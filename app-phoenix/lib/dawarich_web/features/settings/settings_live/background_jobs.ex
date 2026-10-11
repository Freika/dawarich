defmodule DawarichWeb.SettingsLive.BackgroundJobs do
  @moduledoc false
  use DawarichWeb, :live_view
  import DawarichWeb.ListParts, only: [page_header: 1]
  alias Dawarich.Admin.Background
  alias DawarichWeb.{AdminUI, SettingsParts}
  alias Phoenix.LiveView.JS
  embed_templates "background_jobs/*"
  @jobs ~w(start_reverse_geocoding continue_reverse_geocoding)

  @impl true
  def mount(_params, session, socket) do
    operator =
      if connected?(socket),
        do: socket.assigns.operator_context,
        else: static_operator(session, socket)

    socket =
      assign(socket,
        accepted_jobs: MapSet.new(),
        pending_job: nil,
        visits_pending: false,
        dialog_open: false,
        operator_proof: operator,
        params_seen: false,
        data: %{visits: true, notice: false},
        health: nil,
        two_factor: SettingsParts.two_factor_available?(),
        page_title: label(socket.assigns.locale, "background_jobs")
      )

    {:ok, reload(socket)}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{params_seen: false}} = socket),
    do: {:noreply, assign(socket, :params_seen, true)}

  def handle_params(_params, _uri, socket), do: {:noreply, reload(socket)}

  def page(context) do
    with {:ok, data} <-
           Background.page(
             context.current_scope,
             context[:operator_proof] || context[:operator_context]
           ) do
      {:ok,
       %{
         data: Map.drop(data, [:health]),
         health: data.health,
         page_title: label(context.locale, "background_jobs"),
         two_factor: Map.get_lazy(context, :two_factor, &SettingsParts.two_factor_available?/0)
       }}
    end
  end

  @impl true
  def handle_event("open_visits", _, socket),
    do: {:noreply, assign(socket, :visits_pending, true)}

  def handle_event("cancel_visits", _, socket),
    do: {:noreply, assign(socket, :visits_pending, false)}

  def handle_event("update_visits", _, %{assigns: %{visits_pending: false}} = socket),
    do: {:noreply, AdminUI.refuse(socket, :invalid_input)}

  def handle_event("update_visits", _, socket) do
    value = if socket.assigns.data.visits, do: "false", else: "true"

    case Background.update_visits(socket.assigns.current_scope, %{
           "visits_suggestions_enabled" => value
         }) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:visits_pending, false)
         |> reload()
         |> push_event("close-dialog", %{id: "background-visits-confirm"})
         |> AdminUI.notice("controllers.settings.background_jobs.settings_updated")}

      {:error, reason} ->
        {:noreply, AdminUI.refuse(socket, reason)}
    end
  end

  def handle_event("open_job", %{"name" => name}, socket) when name in @jobs,
    do: {:noreply, assign(socket, :pending_job, name)}

  def handle_event("cancel_job", _, socket), do: {:noreply, assign(socket, :pending_job, nil)}

  def handle_event("request_job", _, %{assigns: %{pending_job: nil}} = socket),
    do: {:noreply, AdminUI.refuse(socket, :invalid_input)}

  def handle_event("request_job", _, socket) do
    job = socket.assigns.pending_job

    if MapSet.member?(socket.assigns.accepted_jobs, job) do
      {:noreply, socket}
    else
      case Background.request_job(
             socket.assigns.current_scope,
             job,
             socket.assigns.operator_proof
           ) do
        {:ok, result} ->
          {:noreply,
           socket
           |> assign(:accepted_jobs, MapSet.put(socket.assigns.accepted_jobs, job))
           |> assign(:pending_job, nil)
           |> push_event("close-dialog", %{id: "background-job-confirm"})
           |> AdminUI.notice(result.notice_key)}

        {:error, reason} ->
          {:noreply, AdminUI.refuse(socket, reason)}
      end
    end
  end

  def handle_event(_, _, socket), do: {:noreply, AdminUI.refuse(socket, :invalid_input)}

  defp static_operator(session, %{private: %{connect_info: %Plug.Conn{} = conn}}) do
    session
    |> Map.take(~w(operator_grant operator_login))
    |> Map.put("operator_login", DawarichWeb.OperatorGrant.login(conn))
  end

  defp static_operator(session, _socket), do: Map.take(session, ~w(operator_grant operator_login))

  defp reload(socket) do
    case page(socket.assigns) do
      {:ok, page} -> assign(socket, page)
      {:error, reason} -> AdminUI.refuse(socket, reason)
    end
  end

  @impl true
  def render(assigns), do: index(assigns)
  defp label(locale, key), do: t(locale, "settings.background_jobs.index." <> key, %{})
end
