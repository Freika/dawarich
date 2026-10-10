defmodule Dawarich.Places.Access do
  @moduledoc false
  alias Dawarich.Accounts
  alias Dawarich.Accounts.Scope

  def admit(%Scope{user: %{id: id} = original} = scope) do
    case Accounts.get(id) do
      %{encrypted_password: password} = current when is_binary(password) ->
        if same_identity?(original, current),
          do: {:ok, %{scope | user: current}},
          else: {:error, :stale_session}

      _ ->
        {:error, :stale_session}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def admit(_), do: {:error, :stale_session}

  def settings(scope) do
    if Dawarich.PlaceList.settings?(Dawarich.UserSettings.get(scope.user)),
      do: :ok,
      else: {:error, :unsupported}
  end

  defdelegate same_identity?(original, current), to: Dawarich.Accounts.Principal
end
