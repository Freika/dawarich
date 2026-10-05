defmodule Dawarich.Auth.Account do
  @moduledoc false
  use Ecto.Schema

  schema "users" do
    field(:email, :string)
    field(:api_key, :string, redact: true)
    field(:encrypted_password, :string, redact: true)
    field(:failed_attempts, :integer, default: 0)
    field(:locked_at, :utc_datetime_usec)
    field(:unlock_token, :string, redact: true)
    field(:remember_created_at, :utc_datetime_usec)
    field(:deleted_at, :utc_datetime_usec)
    field(:otp_required_for_login, :boolean, default: false)
    field(:otp_secret, :string, redact: true)
    field(:otp_backup_codes, {:array, :string}, redact: true)
    field(:consumed_timestep, :integer)
    field(:provider, :string)
    field(:uid, :string, redact: true)
    field(:status, :integer)
    field(:plan, :integer)
    field(:subscription_source, :integer)
    field(:active_until, :utc_datetime_usec)
    field(:sign_in_count, :integer, default: 0)
    field(:current_sign_in_at, :utc_datetime_usec)
    field(:last_sign_in_at, :utc_datetime_usec)
    field(:current_sign_in_ip, :string)
    field(:last_sign_in_ip, :string)
    field(:updated_at, :utc_datetime_usec)
    field(:reset_password_token, :string, redact: true)
    field(:reset_password_sent_at, :utc_datetime_usec)
    field(:failed_otp_attempts, :integer)
    field(:otp_locked_at, :utc_datetime_usec)
    field(:settings, :map, redact: true, load_in_query: false)
  end

  def normalize_email(email), do: email |> String.downcase() |> strip()
  def strip(value), do: Regex.replace(~r/\A[\x00\x09-\x0D ]+|[\x00\x09-\x0D ]+\z/, value, "")
end
