defmodule Dawarich.Auth.Providers.Conflicts do
  @moduledoc false
  alias Dawarich.Auth.Account
  alias Dawarich.Repo

  def identity(provider, uid, context),
    do: Map.get(context, :repo, Repo).get_by(Account, [provider: provider, uid: uid], log: false)

  def email("", _), do: nil

  def email(email, context),
    do: Map.get(context, :repo, Repo).get_by(Account, [email: email], log: false)

  def account(%{deleted_at: deleted}, _) when not is_nil(deleted), do: {:error, :pending_deletion}
  def account(user, created), do: {:ok, user, created}
end
