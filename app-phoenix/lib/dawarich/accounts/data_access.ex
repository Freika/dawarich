defmodule Dawarich.Accounts.DataAccess do
  @moduledoc false
  alias Dawarich.Accounts
  alias Dawarich.Accounts.{Principal, Scope}

  @memo {__MODULE__, :request_users}
  @read ~r/\A\s*(select|with|begin|commit|savepoint|release|rollback)\b/i
  @write ~r/\b(insert|update|delete|merge)\b/i

  def with_request_memo(fun) do
    previous = Process.put(@memo, %{})

    try do
      fun.()
    after
      if previous, do: Process.put(@memo, previous), else: Process.delete(@memo)
    end
  end

  def cached(id) do
    case Process.get(@memo) do
      %{^id => user} -> user
      _ -> nil
    end
  end

  def memo_open?, do: is_map(Process.get(@memo))

  def open_memo, do: Process.put(@memo, %{})

  def close_memo, do: Process.delete(@memo)

  def remember_settings(id, raw) do
    with %{} = memo <- Process.get(@memo),
         do: Process.put(@memo, Map.put(memo, {:settings, id}, raw))

    raw
  end

  def cached_settings(id) do
    case Process.get(@memo) do
      %{{:settings, ^id} => raw} -> {:ok, raw}
      _ -> :error
    end
  end

  def remember(%{id: id} = user) do
    with %{} = memo <- Process.get(@memo), do: Process.put(@memo, Map.put(memo, id, user))
    user
  end

  def attach_write_invalidation do
    :telemetry.attach(@memo, [:dawarich, :repo, :query], &__MODULE__.handle_query/4, nil)
  end

  def handle_query(_event, _measurements, %{query: query}, _config) when is_binary(query) do
    if is_map(Process.get(@memo)) and (not (query =~ @read) or query =~ @write),
      do: Process.put(@memo, %{})
  end

  def handle_query(_event, _measurements, _metadata, _config), do: :ok

  def admit(subject, opts \\ [])

  def admit(%Scope{user: %{id: id} = original} = subject, opts) do
    with user when not is_nil(user) <- fresh(id),
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

  defp fresh(id) do
    case Process.get(@memo) do
      %{^id => user} -> user
      %{} -> with %{} = user <- Accounts.get(id), do: remember(user)
      nil -> Accounts.get(id)
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
