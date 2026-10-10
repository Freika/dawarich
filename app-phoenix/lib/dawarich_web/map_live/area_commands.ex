defmodule DawarichWeb.MapLive.AreaCommands do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  import DawarichWeb.Translate, only: [t: 3]
  alias Dawarich.Areas

  @fields ~w(name latitude longitude radius)

  def handle_event("area:new", params, socket) do
    form = %{
      "name" => "",
      "latitude" => coordinate(params["latitude"]),
      "longitude" => coordinate(params["longitude"]),
      "radius" => "100"
    }

    open(socket, %{id: nil, form: form, errors: []})
  end

  def handle_event("area:edit", %{"id" => id}, socket) do
    case Areas.get_area(socket.assigns.current_scope, id) do
      {:ok, area} ->
        form = Map.new(@fields, &{&1, to_string(area[&1])})
        open(socket, %{id: area["id"], form: form, errors: []})

      _ ->
        {:noreply, assign(socket, :area_dialog, nil)}
    end
  end

  def handle_event("area:save", %{"area" => params}, socket) when is_map(params) do
    case socket.assigns[:area_dialog] do
      %{id: id} = dialog ->
        attrs = for key <- @fields, is_binary(params[key]), into: %{}, do: {key, params[key]}
        form = Map.merge(dialog.form, attrs)
        scope = socket.assigns.current_scope

        result =
          if id, do: Areas.update_area(scope, id, form), else: Areas.create_area(scope, form)

        case result do
          {:ok, area} -> saved(socket, area["id"])
          {:error, {:invalid, errors}} -> open(socket, %{dialog | form: form, errors: errors})
          {:error, _} -> open(socket, %{dialog | form: form, errors: [failure(socket)]})
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("area:delete", %{"id" => id}, socket) do
    case Areas.delete_area(socket.assigns.current_scope, id) do
      :ok ->
        saved(socket, id)

      {:error, _} ->
        case socket.assigns[:area_dialog] do
          nil -> {:noreply, socket}
          dialog -> open(socket, %{dialog | errors: [delete_failure(socket)]})
        end
    end
  end

  def handle_event("area:close", _params, socket),
    do: {:noreply, assign(socket, :area_dialog, nil)}

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp open(socket, dialog), do: {:noreply, assign(socket, :area_dialog, dialog)}

  defp saved(socket, id) do
    {:noreply,
     socket
     |> assign(:area_dialog, nil)
     |> push_event("map:invalidate", %{resource: "areas", id: Dawarich.RubyInteger.to_i(id)})}
  end

  defp coordinate(value) when is_number(value), do: to_string(value)
  defp coordinate(value) when is_binary(value), do: value
  defp coordinate(_), do: ""

  defp failure(socket),
    do:
      t(socket.assigns[:locale] || "en", "controllers.api.v1.settings.something_went_wrong", %{})

  defp delete_failure(socket),
    do: t(socket.assigns[:locale] || "en", "javascript.messages.failed_to_delete_area", %{})
end
