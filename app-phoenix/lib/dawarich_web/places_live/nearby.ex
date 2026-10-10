defmodule DawarichWeb.PlacesLive.Nearby do
  @moduledoc false
  import Phoenix.Component
  import Phoenix.LiveView
  alias Dawarich.Places
  alias DawarichWeb.PlacesUI

  def cancel(socket) do
    case socket.assigns[:nearby_state] do
      %{name: name, timer: timer} ->
        Process.cancel_timer(timer)
        socket |> cancel_async(name) |> assign(:nearby_state, nil)

      _ ->
        assign(socket, :nearby_state, nil)
    end
  end

  def request(socket, params) do
    form = socket.assigns.form_state
    current = socket.assigns[:nearby_state]

    if ((connected?(socket) and form) && form.status == :idle) and
         params["generation"] == form.generation and
         (is_nil(current) or current.status != :loading) do
      cs = form.changeset

      request = %{
        "latitude" => text(Ecto.Changeset.get_field(cs, :latitude)),
        "longitude" => text(Ecto.Changeset.get_field(cs, :longitude)),
        "radius" => params["radius"] || "0.5"
      }

      case Dawarich.Places.NearbyInput.parse(request) do
        {:ok, input} -> start(socket, request, input.radius, form.generation)
        _ -> PlacesUI.refuse(socket, :invalid_input)
      end
    else
      socket
    end
  end

  defp start(socket, params, radius, generation) do
    socket = cancel(socket)
    token = make_ref()
    name = {:nearby, generation, token}
    timer = Process.send_after(self(), {:nearby_timeout, generation, token}, 10_000)
    scope = socket.assigns.places_origin

    state = %{
      generation: generation,
      token: token,
      name: name,
      timer: timer,
      radius: radius,
      status: :loading,
      results: [],
      error: nil
    }

    socket
    |> assign(:nearby_state, state)
    |> start_async(name, fn ->
      Places.nearby(scope, params, Application.get_env(:dawarich, :native_places_nearby_opts, []))
    end)
  end

  def finish(socket, {:nearby, generation, token}, result) do
    case socket.assigns[:nearby_state] do
      %{generation: ^generation, token: ^token, status: :loading} = state ->
        Process.cancel_timer(state.timer)

        state =
          case result do
            {:ok, {:ok, results}} ->
              %{state | results: results, status: if(results == [], do: :empty, else: :results)}

            _ ->
              %{
                state
                | results: [],
                  status: :error,
                  error: PlacesUI.message(socket.assigns.locale)
              }
          end

        assign(socket, :nearby_state, state)

      _ ->
        socket
    end
  end

  def timeout(socket, generation, token) do
    case socket.assigns[:nearby_state] do
      %{generation: ^generation, token: ^token, status: :loading} = state ->
        socket
        |> cancel_async(state.name)
        |> assign(:nearby_state, %{
          state
          | status: :error,
            results: [],
            error: PlacesUI.message(socket.assigns.locale)
        })

      _ ->
        socket
    end
  end

  def select(socket, %{"generation" => gen, "index" => index})
      when is_binary(index) and byte_size(index) <= 10 do
    with %{generation: ^gen, status: :idle} = form <- socket.assigns.form_state,
         %{generation: ^gen, status: :results, results: results} <- socket.assigns.nearby_state,
         {index, ""} when index >= 0 <- Integer.parse(index),
         result when is_map(result) <- Enum.at(results, index) do
      attrs = form.changeset.params || %{}

      attrs =
        Map.merge(attrs, %{
          "name" => result.name,
          "latitude" => text(result.latitude),
          "longitude" => text(result.longitude)
        })

      DawarichWeb.PlacesLive.Form.validate(socket, gen, attrs)
    else
      _ -> socket
    end
  end

  def select(socket, _), do: socket
  defp text(value) when is_number(value), do: to_string(value)
  defp text(value), do: value
end
