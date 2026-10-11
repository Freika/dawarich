defmodule DawarichWeb.TagsLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view
  use DawarichWeb, :verified_routes
  import DawarichWeb.Icon, only: [icon: 1]
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Tags

  @impl true
  def mount(_params, _session, socket) do
    tags = Tags.list_tags(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(page_title: nil, tags_count: length(tags))
     |> stream(:tags, tags)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Tags.delete_tag(socket.assigns.current_scope, id) do
      {:ok, tag} ->
        {:noreply,
         socket
         |> stream_delete(:tags, tag)
         |> update(:tags_count, &(&1 - 1))
         |> put_flash(
           :notice,
           t(socket.assigns.locale, "controllers.tags.tag_was_successfully_deleted", %{})
         )}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  def blank?(value), do: Ruby.blank?(value)
end
