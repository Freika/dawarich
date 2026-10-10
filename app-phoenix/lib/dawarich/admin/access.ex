defmodule Dawarich.Admin.Access do
  @moduledoc false

  alias Dawarich.{Accounts, TripSettings, UserTimeZone}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Admin.OperatorGrant

  def admit(scope, mode, opts \\ [])

  def admit(%Scope{user: %{id: id} = original} = scope, mode, opts)
      when mode in [:admin, :background] do
    env = Keyword.get(opts, :env, System.get_env())
    user = Accounts.get(id)

    cond do
      is_nil(user) or not same_identity?(original, user) -> {:error, :stale_session}
      not hosted?(user, mode, env, opts[:operator]) -> {:error, :cloud}
      mode == :admin and user.admin != true -> {:error, :unauthorized}
      not supported?(user) -> {:error, :unsupported}
      opts[:write] == true and Dawarich.Auth.Admission.oidc?(env) -> {:error, :oidc}
      true -> {:ok, %{scope | user: user}}
    end
  end

  def admit(_scope, _mode, _opts), do: {:error, :stale_session}

  def supported?(user) do
    settings = Dawarich.UserSettings.get(user)

    case TripSettings.read(settings) do
      {:ok, _} ->
        zone = settings["timezone"] || System.get_env("TIME_ZONE", "Europe/Berlin")
        TripSettings.zone?(%{"timezone" => zone}, UserTimeZone.name(settings))

      _ ->
        false
    end
  rescue
    _ -> false
  end

  def same_identity?(%{encrypted_password: original}, %{encrypted_password: current})
      when is_binary(original) and is_binary(current),
      do: Plug.Crypto.secure_compare(String.slice(original, 0, 29), String.slice(current, 0, 29))

  def same_identity?(_, _), do: false

  defp hosted?(user, mode, env, operator),
    do:
      Dawarich.ReleaseMigration.self_hosted?(env) or
        (mode == :background and OperatorGrant.authorized?(user, operator || %{}))
end
