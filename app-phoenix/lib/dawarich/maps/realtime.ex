defmodule Dawarich.Maps.Realtime do
  @moduledoc false
  alias Dawarich.{Maps, RailsMessages}
  alias Dawarich.Maps.Family
  alias Dawarich.Maps.Trip

  def topics(%{kind: :public, capability: capability}, opts) do
    with {:ok, link} <- Dawarich.Maps.PublicGrant.admit(capability, opts, false) do
      topics = %{Dawarich.Sharing.Events.topic(link.id) => "public"}

      topics =
        if link.type == "live",
          do: Map.put(topics, stream(["shared_location", {:shared_link, link.id}]), "public"),
          else: topics

      topics =
        if Dawarich.SharedLinks.FamilyAudience.family_only?(link) do
          Enum.reduce(
            Enum.uniq([link.user_id, capability.viewer_scope.user.id]),
            topics,
            &Map.put(&2, "family:user:#{&1}", "public")
          )
        else
          topics
        end

      {:ok, topics}
    end
  end

  def topics(%{scope: scope} = descriptor, opts) do
    with {:ok, fresh} <- Maps.admit(scope, opts) do
      case descriptor.kind do
        :map ->
          Maps.with_actor(scope, fn user -> {:ok, map_topics(scope, user, opts)} end, opts)

        :trip ->
          with {:ok, _} <- Trip.config(scope, descriptor.trip_id, opts),
               do:
                 {:ok,
                  Map.put(
                    user_topics(fresh.user.id),
                    stream([{:trip, descriptor.trip_id}]),
                    "trip"
                  )}

        :family ->
          with {:ok, _} <- Family.view(scope, opts),
               do: {:ok, %{"family:user:#{fresh.user.id}" => "family"}}

        _ ->
          {:error, :not_found}
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def topics(_, _), do: {:error, :not_found}

  defp map_topics(scope, user, opts) do
    topics = stream_topics(user.id)

    topics =
      if Dawarich.UserSettings.get(user)["live_map_enabled"] == false,
        do: Map.delete(topics, stream(["points", {:user, user.id}])),
        else: topics

    layers = Dawarich.UserSettings.get(user)["enabled_map_layers"] || []

    if "Family Members" in List.wrap(layers) do
      case Family.view(scope, opts) do
        {:ok, _} ->
          Map.put(topics, "family:user:#{user.id}", "family")

        _ ->
          topics
      end
    else
      topics
    end
  end

  defp stream_topics(id),
    do: Map.new(~w(points tracks map_edits), &{stream([&1, {:user, id}]), &1})

  defp user_topics(id) do
    stream_topics(id)
    |> Map.put("imports:user:#{id}:native", "imports")
    |> Map.put("notifications:user:#{id}", "progress")
    |> Map.put("sharing:user:#{id}", "sharing")
  end

  defp stream(parts), do: RailsMessages.broadcasting(parts)
end
