defmodule Dawarich.Accounts.NativeAccess do
  @moduledoc false
  import Ecto.Query
  alias Dawarich.Accounts
  alias Dawarich.Accounts.{Principal, Scope}

  def admit(scope, repo \\ Dawarich.Repo)

  def admit(%Scope{user: %{id: id} = actor} = scope, repo) do
    with %{id: ^id} = user <- current(repo, id),
         true <- Principal.same_identity?(actor, user) do
      {:ok, %{scope | user: Principal.project(user)}}
    else
      _ -> {:error, :stale_session}
    end
  rescue
    ArgumentError -> {:error, :invalid_input}
  end

  def admit(_, _), do: {:error, :stale_session}
  defp current(Dawarich.Repo, id), do: Accounts.get(id)

  defp current(repo, id) do
    user =
      repo.one(from(u in Accounts.User, where: u.id == ^id and is_nil(u.deleted_at)), log: false)

    if user && Accounts.unlocked?(user, DateTime.utc_now()), do: user
  end
end
