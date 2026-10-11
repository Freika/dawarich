defmodule Dawarich.Maps.PublicGrant do
  @moduledoc false
  alias Dawarich.{Maps, SharedLinks}
  alias Dawarich.SharedLinks.FamilyAudience
  alias DawarichWeb.SharedLinkCookie

  def bind(%{grant: _} = capability, _opts), do: {:ok, capability}

  def bind(%{id: id} = capability, opts) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    with link when not is_nil(link) <- SharedLinks.active(id, now),
         :ok <- phrase(link, capability[:proof], now),
         {:ok, viewer} <- viewer(capability[:viewer_scope], opts),
         {:ok, grant} <-
           Dawarich.Sharing.Public.grant(link, viewer, now, due(link, capability, now)) do
      {:ok, Map.put(capability, :grant, grant)}
    else
      {:error, _} = error -> error
      _ -> {:error, :not_found}
    end
  end

  def bind(_, _), do: {:error, :not_found}

  def admit(capability, opts, resource?) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    with {:ok, bound} <- bind(capability, opts),
         link when not is_nil(link) <- SharedLinks.active(bound.id, now),
         :ok <- phrase(link, bound[:proof], now),
         {:ok, viewer} <- viewer(bound[:viewer_scope], opts),
         true <- same_viewer?(bound.grant.viewer, viewer),
         {:ok, admitted} <- Dawarich.Sharing.Public.admit(bound.grant, now),
         :ok <- resource(admitted.kind, resource?) do
      {:ok, admitted.link}
    else
      {:error, _} = error -> error
      _ -> {:error, :not_found}
    end
  end

  defp same_viewer?(nil, nil), do: true

  defp same_viewer?(%{id: id} = original, %{id: id} = current),
    do: Dawarich.Accounts.Principal.same_identity?(original, current)

  defp same_viewer?(_, _), do: false

  defp viewer(nil, _), do: {:ok, nil}

  defp viewer(scope, opts) do
    case Maps.admit(scope, opts) do
      {:ok, fresh} -> {:ok, fresh.user}
      _ -> {:error, :not_found}
    end
  end

  defp phrase(link, proof, now) do
    token = SharedLinkCookie.unlock_token(link.id, link.magic_phrase)

    cond do
      FamilyAudience.family_only?(link) or is_nil(token) ->
        :ok

      is_map(proof) and valid_expiry?(proof["expires_at"], now) and
        is_binary(proof["identity"]) and
          Plug.Crypto.secure_compare(proof["identity"], SharedLinkCookie.proof_identity(token)) ->
        :ok

      true ->
        {:error, :locked}
    end
  end

  defp valid_expiry?(nil, _), do: true

  defp valid_expiry?(raw, now) when is_binary(raw) do
    case DateTime.from_iso8601(raw) do
      {:ok, due, _} -> DateTime.compare(now, due) == :lt
      _ -> false
    end
  end

  defp valid_expiry?(_, _), do: false
  defp resource(:missing_resource, true), do: {:error, :missing_resource}
  defp resource(_, _), do: :ok

  defp due(link, capability, now) do
    [link.expires_at, (capability[:proof] || %{})["expires_at"], DateTime.add(now, 86_400)]
    |> Enum.map(fn
      %DateTime{} = at ->
        at

      %NaiveDateTime{} = at ->
        DateTime.from_naive!(at, "Etc/UTC")

      raw when is_binary(raw) ->
        case DateTime.from_iso8601(raw) do
          {:ok, at, _} -> at
          _ -> nil
        end

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.min_by(&DateTime.to_unix/1)
  end
end
