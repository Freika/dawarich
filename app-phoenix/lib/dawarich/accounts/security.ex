defmodule Dawarich.Accounts.Security do
  @moduledoc false
  alias Dawarich.Accounts.{Scope, User}
  alias Dawarich.Auth.TwoFactor.Closure
  @fields %{show: [], setup: [], verify: ["otp_attempt"], disable: ["password", "otp_attempt"]}

  def manage_two_factor(
        %Scope{user: %User{id: id, encrypted_password: hash}},
        operation,
        fields,
        %{session_salt: salt, pending: false},
        options
      )
      when is_integer(id) and is_binary(hash) and is_binary(salt) and is_map(fields) and
             is_map(options) do
    with true <-
           byte_size(hash) >= 29 and Plug.Crypto.secure_compare(String.slice(hash, 0, 29), salt),
         {:ok, allowed} <- Map.fetch(@fields, operation),
         true <- Enum.all?(fields, fn {key, value} -> key in allowed and is_binary(value) end) do
      operation |> Closure.call(id, salt, fields, Map.put(options, :native, true)) |> present()
    else
      _ -> {:handoff, :identity}
    end
  end

  def manage_two_factor(_, _, _, _, _), do: {:handoff, :identity}

  defp present({status, %{user: user} = result}) when status in [:ok, :error] do
    {status,
     result
     |> Map.delete(:user)
     |> Map.merge(%{enabled: user.otp_required_for_login, status: user.status})}
  end

  defp present({:unavailable, _}), do: {:unavailable, nil}
  defp present(result), do: result
end
