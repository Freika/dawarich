defmodule Dawarich.Auth.TwoFactor.Management do
  @moduledoc false
  alias Dawarich.Auth.TwoFactor.{BackupCodes, Secret, Totp}
  alias Dawarich.Auth.Recovery.Token
  alias Dawarich.{QrCode, Repo}

  def show(id, salt, context \\ %{}) do
    with {:ok, user, _secret} <- ready(id, salt, context),
         do: {:ok, %{kind: :show, user: user}}
  end

  def setup(id, salt, context \\ %{}) do
    with {:ok, user, _secret} <- ready(id, salt, context),
         secret <-
           Totp.generate_secret(
             Map.get(context, :secret_entropy, fn -> :crypto.strong_rand_bytes(20) end).()
           ),
         {:ok, form} <- form(user, secret),
         {:ok, ciphertext} <- Secret.encrypt(secret, environment(context)) do
      user = persist(user, %{otp_secret: ciphertext}, context)
      {:ok, %{form | user: user}}
    end
  end

  def verify(id, salt, code, context \\ %{}) do
    with {:ok, user, secret} <- ready(id, salt, context),
         {:ok, form} <- form(user, secret) do
      now = clock(context)

      case Totp.verify(secret, code, DateTime.to_unix(now), user.consumed_timestep) do
        :invalid ->
          {:error, Map.put(form, :reason, :invalid_verification_code)}

        {:ok, timestep} ->
          enable(user, timestep, context)
      end
    end
  end

  def disable(id, salt, password, code, context \\ %{}) do
    with {:ok, user, secret} <- ready(id, salt, context) do
      if valid_password?(password, user.encrypted_password) do
        case consume(user, secret, code || "", context) do
          {:ok, user} ->
            user =
              persist(
                user,
                %{otp_required_for_login: false, otp_secret: nil, otp_backup_codes: nil},
                context
              )

            {:ok, %{kind: :redirect, reason: :two_factor_authentication_disabled, user: user}}

          :invalid ->
            {:error,
             %{kind: :redirect, reason: :provide_a_valid_two_factor_code_or_backup_code_to}}
        end
      else
        {:error, %{kind: :redirect, reason: :incorrect_password}}
      end
    end
  end

  defp valid_password?(password, hash) when is_binary(password),
    do:
      not Token.blank?(password) and
        Bcrypt.verify_pass(binary_part(password, 0, min(byte_size(password), 72)), hash)

  defp valid_password?(_, _), do: false

  def consume(user, secret, code, context) do
    case Totp.verify(secret, code, DateTime.to_unix(clock(context)), user.consumed_timestep) do
      {:ok, timestep} ->
        {:ok, persist(user, %{consumed_timestep: timestep}, context)}

      :invalid ->
        case BackupCodes.consume(
               user.otp_backup_codes,
               code,
               Map.get(context, :backup_options, [])
             ) do
          {:ok, hashes} -> {:ok, persist(user, %{otp_backup_codes: hashes}, context)}
          :invalid -> :invalid
        end
    end
  end

  defp enable(user, timestep, context) do
    user = persist(user, %{consumed_timestep: timestep}, context)
    {:ok, codes, hashes} = BackupCodes.generate(Map.get(context, :backup_options, []))
    user = persist(user, %{otp_required_for_login: true, otp_backup_codes: hashes}, context)
    {:ok, %{kind: :backup_codes, user: user, codes: codes}}
  end

  defp ready(id, salt, context) do
    with {:ok, user} <- Secret.actor(id, salt, context) do
      if Secret.available?(environment(context)) do
        with {:ok, secret} <- Secret.decrypt(user.otp_secret, environment(context)),
             true <- BackupCodes.supported?(user.otp_backup_codes),
             :ok <- readable(secret) do
          {:ok, user, secret}
        else
          false -> {:handoff, :backup_state}
          other -> other
        end
      else
        {:unavailable, user}
      end
    end
  end

  defp readable(nil), do: :ok

  defp readable(secret) do
    Totp.decode(secret)
    :ok
  rescue
    ArgumentError -> {:handoff, :secret}
  end

  defp form(_user, nil), do: {:handoff, :secret}

  defp form(user, secret) do
    uri = Totp.provisioning_uri(secret, user.email)
    QrCode.modules(uri)
    {:ok, %{kind: :verify, user: user, secret: secret, uri: uri}}
  rescue
    ArgumentError -> {:handoff, :render}
  end

  defp persist(user, changes, context) do
    changes = Map.put(changes, :updated_at, clock(context))
    user |> Ecto.Changeset.change(changes) |> Map.get(context, :repo, Repo).update!(log: false)
  end

  defp environment(context), do: Map.get_lazy(context, :env, &System.get_env/0)
  defp clock(context), do: Map.get(context, :clock, &DateTime.utc_now/0).()
end
