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

  defp same_identity?(%{encrypted_password: original}, %{encrypted_password: current})
       when is_binary(original) and is_binary(current),
       do: Plug.Crypto.secure_compare(String.slice(original, 0, 29), String.slice(current, 0, 29))

  defp same_identity?(_, _), do: false
end
