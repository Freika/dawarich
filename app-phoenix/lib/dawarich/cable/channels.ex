defmodule Dawarich.Cable.Channels do
  @moduledoc false

  import Ecto.Query

  alias Dawarich.{Entitlements, RailsMessages, Repo}

  @user_channels %{
    "PointsChannel" => "points",
    "TracksChannel" => "tracks",
    "ImportsChannel" => "imports",
    "MapEditsChannel" => "map_edits"
  }
  @names ~w(PointsChannel TracksChannel ImportsChannel MapEditsChannel FamilyLocationsChannel SharedLocationChannel Turbo::StreamsChannel ApplicationCable::Channel)

  def authorize(%{"channel" => "::" <> name} = params, identity, context) when name in @names,
    do: channel(name, params, identity, context)

  def authorize(%{"channel" => name} = params, identity, context) when name in @names,
    do: channel(name, params, identity, context)

  def authorize(_params, _identity, _context), do: :ignore

  defp channel(name, _params, %{user: %{id: id}}, _context) when is_map_key(@user_channels, name),
    do: {:stream, RailsMessages.broadcasting([@user_channels[name], {:user, id}])}

  defp channel(name, _params, _identity, _context) when is_map_key(@user_channels, name),
    do: :reject

  defp channel("FamilyLocationsChannel", _params, %{user: %{} = user}, context) do
    with true <- Entitlements.families?(user, context.self_hosted, context.now.()),
         family when is_integer(family) <- family_id(user.id) do
      {:stream, RailsMessages.broadcasting(["family_locations", {:family, family}])}
    else
      _ -> :reject
    end
  end

  defp channel("FamilyLocationsChannel", _params, _identity, _context), do: :reject

  defp channel("SharedLocationChannel", %{"share_id" => id}, %{share: %{id: id}}, _context)
       when is_binary(id),
       do: {:stream, RailsMessages.broadcasting(["shared_location", {:shared_link, id}])}

  defp channel("SharedLocationChannel", _params, _identity, _context), do: :reject

  defp channel("Turbo::StreamsChannel", params, _identity, context) do
    case params["signed_stream_name"] do
      signed when is_binary(signed) or is_nil(signed) ->
        case RailsMessages.verified_stream_name(signed, context.secret) do
          {:ok, name} -> {:stream, name}
          :error -> :reject
        end

      _other ->
        :ignore
    end
  end

  defp channel("ApplicationCable::Channel", _params, _identity, _context), do: :confirm

  defp family_id(user_id),
    do:
      Repo.one(
        from m in "family_memberships",
          where: m.user_id == ^user_id,
          select: m.family_id,
          limit: 1
      )
end
