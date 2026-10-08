defmodule DawarichWeb.TagsLive.Form do
  @moduledoc false
  use DawarichWeb, :live_view
  use DawarichWeb, :verified_routes

  import DawarichWeb.CoreComponents
  import DawarichWeb.Icon, only: [icon: 1]

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Tags
  alias Ecto.Changeset

  @colors ~w(#ef4444 #f97316 #f59e0b #eab308 #84cc16 #22c55e #10b981 #14b8a6 #06b6d4 #0ea5e9 #3b82f6 #6366f1 #8b5cf6 #a855f7 #d946ef #ec4899 #f43f5e #64748b)
  @default_color "#6ab0a4"

  @impl true
  def mount(_params, session, socket),
    do:
      {:ok,
       assign(socket,
         default_emoji: session["tag_default_emoji"] || DawarichWeb.TagEmoji.random(),
         colors: @colors
       )}

  @impl true
  def handle_params(params, _uri, socket) do
    scope = socket.assigns.current_scope

    tag =
      case socket.assigns.live_action do
        :new ->
          %{Tags.new_tag() | icon: socket.assigns.default_emoji, color: @default_color}

        :edit ->
          case Tags.get_tag(scope, params["id"]) do
            {:ok, tag} -> with_defaults(tag)
            {:error, :not_found} -> raise DawarichWeb.NotFoundError
          end
      end

    kind = if tag.id, do: "edit", else: "new"

    {:noreply,
     socket
     |> assign(
       tag: tag,
       kind: kind,
       page_title: nil,
       privacy: not is_nil(tag.privacy_radius_meters)
     )
     |> assign(:tag_title, t(socket.assigns.locale, "tags.#{kind}.#{kind}_tag", %{}))
     |> assign_form(Tags.change_tag(scope, tag))}
  end

  @impl true
  def handle_event("validate", %{"tag" => params} = event, socket) do
    params = chosen_color(params, event["_target"])

    changeset =
      socket.assigns.current_scope
      |> Tags.change_tag(socket.assigns.tag, params)
      |> Map.put(:action, :validate)
      |> keep_unused_markers(params)

    {:noreply,
     socket |> assign(:privacy, params["privacy_enabled"] == "true") |> assign_form(changeset)}
  end

  def handle_event("save", %{"tag" => params}, socket) do
    scope = socket.assigns.current_scope

    result =
      if socket.assigns.tag.id,
        do: Tags.update_tag(scope, socket.assigns.tag, params),
        else: Tags.create_tag(scope, params)

    case result do
      {:ok, _tag} ->
        kind = if socket.assigns.tag.id, do: "updated", else: "created"

        {:noreply,
         socket
         |> put_flash(
           :notice,
           t(socket.assigns.locale, "controllers.tags.tag_was_successfully_#{kind}", %{})
         )
         |> push_navigate(to: ~p"/tags")}

      {:error, %Changeset{} = changeset} ->
        {:noreply,
         socket |> assign(:privacy, params["privacy_enabled"] == "true") |> assign_form(changeset)}

      {:error, :not_found} ->
        raise DawarichWeb.NotFoundError
    end
  end

  defp chosen_color(params, ["tag", "custom_color"]),
    do: Map.put(params, "color", params["custom_color"])

  defp chosen_color(params, _target), do: params

  defp keep_unused_markers(changeset, params) do
    unused = Map.filter(params, fn {key, _} -> String.starts_with?(key, "_unused_") end)
    %{changeset | params: Map.merge(changeset.params || %{}, unused)}
  end

  defp submitted_errors(%Changeset{action: action, errors: errors})
       when action in [:insert, :update],
       do: Enum.map(errors, fn {_field, {message, _}} -> message end)

  defp submitted_errors(_changeset), do: []

  defp assign_form(socket, changeset) do
    color = Changeset.get_field(changeset, :color) || @default_color
    radius = Changeset.get_field(changeset, :privacy_radius_meters)

    assign(socket,
      form: to_form(changeset, as: :tag, id: "tag-form"),
      icon: Changeset.get_field(changeset, :icon),
      color: color,
      custom: color not in @colors,
      radius: if(Ruby.blank?(radius), do: "1000", else: radius),
      errors: submitted_errors(changeset)
    )
  end

  defp with_defaults(tag) do
    %{
      tag
      | icon: if(Ruby.blank?(tag.icon), do: "🏠", else: tag.icon),
        color: if(Ruby.blank?(tag.color), do: @default_color, else: tag.color)
    }
  end
end
