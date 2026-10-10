defmodule DawarichWeb.NativePosterGallery do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3, update: 3]
  import Phoenix.LiveView, only: [connected?: 1, put_flash: 3]

  alias Dawarich.Posters
  alias Dawarich.Posters.Dependencies.Progress
  alias DawarichWeb.Translate

  def mount(socket) do
    scope = socket.assigns.current_scope
    if connected?(socket), do: Progress.subscribe(scope.user.id)

    posters =
      case Posters.gallery(scope) do
        {:ok, posters} -> posters
        {:error, _} -> []
      end

    assign(socket, :posters, posters)
  end

  def handle_event("poster:save", recipe, socket) do
    case Posters.create(socket.assigns.current_scope, recipe) do
      {:ok, card} ->
        {:reply, %{status: "queued"},
         socket
         |> update(:posters, &[card | Enum.reject(&1, fn poster -> poster.id == card.id end)])
         |> put_flash(
           :info,
           notice(socket, "poster_generation_started_this_takes_about_a_minute")
         )}

      {:error, _} ->
        {:reply, %{status: "failed"},
         put_flash(socket, :error, notice(socket, "failed_to_start_poster_generation"))}
    end
  end

  def handle_event("poster:delete", %{"id" => id}, socket) do
    case Posters.delete(socket.assigns.current_scope, id) do
      {:ok, id} -> {:noreply, update(socket, :posters, &reject(&1, id))}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("poster:delete", _params, socket), do: {:noreply, socket}

  def handle_info(message, socket) do
    with %{user: %{id: user_id}} <- socket.assigns[:current_scope],
         {:ok, id} <- Progress.changed(message, user_id) do
      {:noreply, refresh(socket, id)}
    else
      _ -> :unhandled
    end
  end

  defp refresh(socket, id) do
    if Enum.any?(socket.assigns.posters, &(&1.id == id)) do
      case Posters.card(socket.assigns.current_scope, id) do
        {:ok, card} ->
          update(socket, :posters, &Enum.map(&1, fn p -> if p.id == id, do: card, else: p end))

        {:error, :not_found} ->
          update(socket, :posters, &reject(&1, id))

        {:error, _} ->
          socket
      end
    else
      socket
    end
  end

  defp reject(posters, id), do: Enum.reject(posters, &(&1.id == id))

  defp notice(socket, key),
    do: Translate.t(socket.assigns.current_scope.locale, "controllers.posters." <> key, %{})
end
