defmodule Dawarich.Cable.Identity do
  @moduledoc false

  import Ecto.Query

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Repo

  @acceptable ~r/\A(\{)?([a-fA-F0-9]{4}-?){8}(?(1)\}|)\z/
  @canonical ~r/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/
  @live 3

  def resolve(user, share_param, unlocked?, now) do
    {:ok, share} = share(share_param, unlocked?, now)
    identify(user, share)
  end

  def share(param, unlocked?, now) do
    cond do
      Ruby.blank?(param) -> {:ok, nil}
      is_binary(param) -> lookup([cast(param)], unlocked?, now)
      is_list(param) -> lookup(Enum.map(param, &(is_binary(&1) && cast(&1))), unlocked?, now)
      true -> {:ok, nil}
    end
  end

  def cast(value) do
    cond do
      not Regex.match?(@acceptable, value) -> nil
      Regex.match?(@canonical, value) -> value
      true -> value |> String.replace(["{", "}", "-"], "") |> String.downcase() |> hyphenate()
    end
  end

  defp identify({:locked, _user}, _share), do: :silent
  defp identify(%{} = user, share), do: {:ok, %{user: user, share: share}}
  defp identify(nil, nil), do: :unauthorized
  defp identify(nil, share), do: {:ok, %{user: nil, share: share}}

  defp hyphenate(<<a::binary-8, b::binary-4, c::binary-4, d::binary-4, e::binary>>),
    do: Enum.join([a, b, c, d, e], "-")

  defp lookup(ids, unlocked?, now) do
    case Enum.filter(ids, &is_binary/1) do
      [] -> {:ok, nil}
      ids -> {:ok, ids |> active(DateTime.to_naive(now)) |> unlocked(unlocked?)}
    end
  end

  defp active(ids, now) do
    Repo.one(
      from s in "shared_links",
        where:
          s.id in type(^ids, {:array, Ecto.UUID}) and s.resource_type == @live and
            is_nil(s.revoked_at) and (is_nil(s.expires_at) or s.expires_at > ^now),
        limit: 1,
        select: %{id: type(s.id, Ecto.UUID), magic_phrase: s.magic_phrase}
    )
  end

  defp unlocked(nil, _unlocked?), do: nil

  defp unlocked(share, unlocked?),
    do: if(Ruby.blank?(share.magic_phrase) or unlocked?.(share), do: share)
end
