defmodule Dawarich.Admin.Users do
  @moduledoc false

  alias Dawarich.Accounts.User
  alias Dawarich.Admin.{Access, UsersPage}

  def list(scope, query) do
    with {:ok, scope} <- Access.admit(scope, :admin) do
      UsersPage.list(scope.user, query, :native)
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def get(scope, id, kind) do
    with {:ok, scope} <- Access.admit(scope, :admin),
         {:ok, target} <- UsersPage.find(scope.user, target_id(id), kind, :native) do
      if kind == :show do
        {:ok,
         %{
           user: struct(User, Map.take(target, [:id, :email, :admin, :status, :api_key])),
           details: Map.drop(target, [:api_key, :counts]),
           counts: target.counts
         }}
      else
        {:ok, target}
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp target_id(id) when is_integer(id), do: id

  defp target_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp target_id(_), do: nil
end
