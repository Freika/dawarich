defmodule DawarichWeb.ImportsLive.Edit do
  @moduledoc false
  use DawarichWeb, :live_view

  @impl true
  def mount(_, _, socket) do
    if connected?(socket), do: Dawarich.Imports.subscribe(socket.assigns.current_scope)
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    case Dawarich.Imports.get(socket.assigns.current_scope, id) do
      {:ok, record} ->
        {:noreply, assign(socket, record: record, page_title: nil, invalid_source: false)}

      _ ->
        {:noreply, socket |> assign(record: nil) |> redirect(to: "/imports")}
    end
  end

  @impl true
  def handle_info({:domain_changed, owner, :imports}, socket)
      when owner == socket.assigns.current_user.id do
    DawarichWeb.ImportsInvalidations.coalesce(owner)
    handle_params(%{"id" => socket.assigns.record.id}, "", socket)
  end

  @impl true
  def handle_event("save_import", %{"import" => params}, socket) do
    case Dawarich.Imports.update(socket.assigns.current_scope, socket.assigns.record.id, params) do
      {:ok, _} ->
        success(socket)

      {:error, reason} when reason in [:invalid_name, :duplicate_name] ->
        success(socket)

      {:error, reason} ->
        {:noreply, assign(socket, invalid_source: reason == :invalid_source)}
    end
  end

  defp success(socket) do
    {:noreply,
     socket
     |> put_flash(
       :notice,
       t(socket.assigns.locale, "controllers.imports.import_was_successfully_updated", %{})
     )
     |> push_navigate(to: "/imports")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <DawarichWeb.ImportEdit.form
      record={@record}
      locale={@locale}
      csrf={@rails_csrf_token}
      native={true}
      invalid_source={@invalid_source}
    />
    """
  end
end
