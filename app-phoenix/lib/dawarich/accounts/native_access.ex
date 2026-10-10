defmodule Dawarich.Accounts.NativeAccess do
  @moduledoc false
  alias Dawarich.Accounts
  alias Dawarich.Accounts.{Principal, Scope}

  def admit(%Scope{user: %{id: id} = actor} = scope) do
    with %{id: ^id} = user <- Accounts.get(id),
         true <- Principal.same_identity?(actor, user) do
      {:ok, %{scope | user: Principal.project(user)}}
    else
      _ -> {:error, :stale_session}
    end
  end

  def admit(_), do: {:error, :stale_session}
end
