defmodule Dawarich.Auth.TwoFactor.ApiWrite do
  @moduledoc false
  alias Dawarich.Auth.Recovery.Token
  alias Dawarich.Auth.TwoFactor.{BackupCodes, Management, Secret, Totp}
  alias Dawarich.{I18n, Repo}

  def setup(user, context) do
    secret =
      Totp.generate_secret(
        Map.get(context, :secret_entropy, fn -> :crypto.strong_rand_bytes(20) end).()
      )

    {:ok, ciphertext} = Secret.encrypt(secret, Map.get_lazy(context, :env, &System.get_env/0))
    user = persist(user, %{otp_secret: ciphertext}, context)

    {:ok, 200,
     {:object,
      [{"provisioning_uri", Totp.provisioning_uri(secret, user.email)}, {"secret", secret}]}}
  end

  def confirm(user, code, context) do
    {:ok, secret} =
      Secret.decrypt(user.otp_secret, Map.get_lazy(context, :env, &System.get_env/0))

    now = Map.get(context, :clock, &DateTime.utc_now/0).()

    case Totp.api_verify(secret, code, DateTime.to_unix(now)) do
      {:ok, _timestep} ->
        {:ok, codes, hashes} = BackupCodes.generate(Map.get(context, :backup_options, []))
        persist(user, %{otp_required_for_login: true, otp_backup_codes: hashes}, context)
        {:ok, 200, {:object, [{"backup_codes", codes}]}}

      :invalid ->
        {:ok, 422, {:object, [{"error", "invalid_otp"}]}}
    end
  end

  def backup_codes(user, context) do
    {:ok, codes, hashes} = BackupCodes.generate(Map.get(context, :backup_options, []))
    persist(user, %{otp_backup_codes: hashes}, context)
    {:ok, 200, {:object, [{"backup_codes", codes}]}}
  end

  def destroy(user, code, context) do
    {:ok, secret} =
      Secret.decrypt(user.otp_secret, Map.get_lazy(context, :env, &System.get_env/0))

    consumed =
      if Token.blank?(code), do: :invalid, else: Management.consume(user, secret, code, context)

    case consumed do
      {:ok, user} ->
        persist(
          user,
          %{otp_secret: nil, otp_required_for_login: false, otp_backup_codes: []},
          context
        )

        {:ok, 200, {:object, [{"message", message("two_factor_authentication_disabled")}]}}

      :invalid ->
        {:ok, 401,
         {:object,
          [
            {"error", "otp_required"},
            {"message", message("provide_a_valid_two_factor_code_or_backup_code_to")}
          ]}}
    end
  end

  defp message(key), do: I18n.en!("controllers.api.v1.users.two_factor." <> key)

  defp persist(user, changes, context) do
    changes = Map.put(changes, :updated_at, Map.get(context, :clock, &DateTime.utc_now/0).())
    user |> Ecto.Changeset.change(changes) |> Map.get(context, :repo, Repo).update!(log: false)
  end
end
