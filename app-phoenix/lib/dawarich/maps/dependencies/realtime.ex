defmodule Dawarich.Maps.Dependencies.Realtime do
  @moduledoc false
  alias Dawarich.{Maps, RailsMessages}
  alias Dawarich.Maps.Dependencies.{Family, Public, Trip}

  def topics(%{kind: :public, capability: capability}, opts) do
    case Public.config(capability, opts) do
      {:ok, %{"publicType" => "live"}} ->
        {:ok, %{stream(["shared_location", {:shared_link, capability.id}]) => "public"}}

      {:ok, _} ->
        {:ok, %{}}

      {:error, _} = error ->
        error
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
          Maps.with_actor(
            scope,
            fn user ->
              case Dawarich.FamilyPage.read(user, :show,
                     now: Keyword.get(opts, :now, DateTime.utc_now()),
                     self_hosted:
                       Keyword.get(opts, :self_hosted, DawarichWeb.LayoutAssigns.self_hosted?())
                   ) do
                {:ok, %{state: :show, family: %{id: id}}} ->
                  {:ok, %{stream(["family_locations", {:family, id}]) => "family"}}

                _ ->
                  {:error, :not_found}
              end
            end,
            opts
          )

        _ ->
          {:error, :not_found}
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def topics(_, _), do: {:error, :not_found}

  defp map_topics(scope, user, opts) do
    topics = user_topics(user.id)

    topics =
      if Dawarich.UserSettings.get(user)["live_map_enabled"] == false,
        do: Map.delete(topics, stream(["points", {:user, user.id}])),
        else: topics

    layers = Dawarich.UserSettings.get(user)["enabled_map_layers"] || []

    if "Family Members" in List.wrap(layers) do
      case Family.view(scope, opts) do
        {:ok, %{presentation: %{family: %{id: id}}}} ->
          Map.put(topics, stream(["family_locations", {:family, id}]), "family")

        _ ->
          topics
      end
    else
      topics
    end
  end

  defp user_topics(id) do
    Map.new(~w(points tracks imports map_edits), &{stream([&1, {:user, id}]), &1})
    |> Map.put(stream([{:user, id}]), "progress")
  end

  defp stream(parts), do: RailsMessages.broadcasting(parts)
end
