defmodule DawarichWeb.TripsLive.Form do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Dawarich.Trips.WebForm
  alias DawarichWeb.TripForm

  def mount(params, _session, socket) do
    id = params["id"] && String.to_integer(params["id"])

    case WebForm.load(Dawarich.Repo, socket.assigns.current_user, id, socket.assigns) do
      {:ok, form} ->
        title =
          t(
            socket.assigns.locale,
            if(id, do: "trips.edit.editing_trip", else: "trips.new.new_trip"),
            %{}
          )

        {:ok,
         assign(socket,
           form: form,
           page_title: title,
           rails_js: true,
           rails_trix: true,
           rails_charts: false
         ), temporary_assigns: [form: nil]}

      _ ->
        {:ok, redirect(socket, to: socket.assigns.request_path)}
    end
  end

  def render(assigns) do
    ~H"""
    <div
      id="trip-form-shell"
      class="contents"
      phx-hook="MapShell"
      phx-update="ignore"
      data-turbo="true"
    >
      <TripForm.page form={@form} locale={@locale} csrf={@rails_csrf_token} base_url={@base_url} />
    </div>
    """
  end
end
