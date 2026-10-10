defmodule Dawarich.Achievements.Commands do
  @moduledoc false
  alias Dawarich.Accounts.DataAccess
  alias Dawarich.Achievements.{Celebrations, Deck, Pages, Sharing, UiText}
  alias Dawarich.Repo

  def acknowledge(subject, params, opts \\ []) do
    write(subject, fn scope ->
      with {:ok, page} <- Pages.load(scope, params, opts) do
        :ok =
          Celebrations.record_seen!(Repo, scope.user.id, page.celebrations, fn ->
            UiText.timestamp(scope.user.settings, now(opts))
          end)

        {:ok, page.celebrations}
      end
    end)
  end

  def share(subject, key, attrs, opts \\ []) do
    write(subject, fn scope ->
      case Sharing.call(Repo, scope.user.id, key, attrs, %{clock: fn -> now(opts) end}) do
        {:ok, %{enabled: enabled, uuid: uuid}} ->
          {:ok, %{enabled: enabled, url: "/shared/achievements/" <> uuid}}

        {:unsupported, _} ->
          {:error, :invalid_input}

        other ->
          other
      end
    end)
  end

  def claim(subject, params, opts \\ []),
    do:
      write(subject, fn scope ->
        {:ok, Deck.claim(Repo, scope.user.id, params, %{clock: fn -> now(opts) end})}
      end)

  def seen(subject, id, token, opts \\ []),
    do:
      write(subject, fn scope ->
        {:ok, Deck.acknowledge(Repo, scope.user.id, id, token, %{clock: fn -> now(opts) end})}
      end)

  def dismiss(subject, bound, opts \\ []),
    do:
      write(subject, fn scope ->
        {:ok, Deck.dismiss_through(Repo, scope.user.id, bound, %{clock: fn -> now(opts) end})}
      end)

  defp write(subject, fun) do
    with {:ok, scope} <- DataAccess.admit(subject, settings: true) do
      case Repo.transaction(fn ->
             Repo.query!("SELECT id FROM users WHERE id=$1 FOR UPDATE", [scope.user.id],
               log: false
             )

             with {:ok, fresh} <- DataAccess.admit(subject, settings: true), do: fun.(fresh)
           end) do
        {:ok, result} -> result
        {:error, _} -> {:error, :unavailable}
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp now(opts), do: Keyword.get(opts, :now, DateTime.utc_now())
end
