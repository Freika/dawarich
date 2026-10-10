defmodule Dawarich.Accounts.DataAccess do
  @moduledoc false
  alias Dawarich.Accounts
  alias Dawarich.Accounts.{Principal, Scope}

  def admit(subject, opts \\ [])

  def admit(%Scope{user: %{id: id} = original} = subject, opts) do
    with user when not is_nil(user) <- Accounts.get(id),
         true <- Principal.same_identity?(original, user),
         scope = %{subject | user: user},
         :ok <- settings(scope, opts),
         :ok <- active(scope, opts),
         :ok <- entitlement(scope, opts) do
      {:ok, scope}
    else
      {:error, _} = error -> error
      _ -> {:error, :stale_session}
    end
  end

  def admit(_, _), do: {:error, :stale_session}

  defp settings(scope, opts) do
    if opts[:settings] == true and not Dawarich.Admin.Access.supported?(scope.user),
      do: {:error, :unsupported},
      else: :ok
  end

  defp active(scope, opts) do
    if opts[:active] == true and scope.user.status != 1,
      do: {:error, :unauthorized},
      else: :ok
  end

  defp entitlement(scope, opts) do
    hosted =
      Keyword.get(opts, :self_hosted, Dawarich.ReleaseMigration.self_hosted?(System.get_env()))

    now = Keyword.get(opts, :now, DateTime.utc_now())

    if opts[:full_access] == true and
         not Dawarich.Entitlements.full_access?(scope.user, hosted, now),
       do: {:error, :unauthorized},
       else: :ok
  end
end
