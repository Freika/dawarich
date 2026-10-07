defmodule Dawarich.Auth.Remember do
  @moduledoc false
  alias Dawarich.Accounts

  def valid?(user, payload, now),
    do: Accounts.remembered?(user, payload, now) and Accounts.unlocked?(user, now)

  def forget(repo, user, now) do
    if user && user.remember_created_at do
      repo.update!(Ecto.Changeset.change(user, %{remember_created_at: nil, updated_at: now}),
        log: false
      )
    end

    :ok
  end
end
