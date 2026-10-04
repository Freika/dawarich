defmodule DawarichWeb.ImportsLive.Edit do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Dawarich.Imports.UiRecords
  alias DawarichWeb.ImportsContext

  @impl true
  def mount(_, _, socket), do: {:ok, socket}

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    case UiRecords.get(ImportsContext.repo(), socket.assigns.current_user.id, id) do
      {:ok, record} -> {:noreply, assign(socket, record: record, page_title: nil)}
      _ -> {:noreply, redirect(socket, to: "/imports")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <DawarichWeb.ImportEdit.form record={@record} locale={@locale} csrf={@rails_csrf_token} />
    """
  end
end
