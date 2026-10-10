defmodule Dawarich.Accounts.DataAccess do
  @moduledoc false
  alias Dawarich.Accounts.Scope
  alias Dawarich.NativeM5.Dependencies

  def admit(subject, opts \\ [])
  def admit(%Scope{} = scope, opts), do: admit(Dependencies.principal(scope), opts)

  def admit(subject, opts) do
    with {:ok, scope} <- Dependencies.admit(subject),
         :ok <- settings(scope, opts),
         :ok <- active(scope, opts),
         :ok <- entitlement(scope, opts) do
      {:ok, scope}
    end
  end

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
