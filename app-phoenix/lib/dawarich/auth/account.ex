defmodule Dawarich.Auth.Account do
  @moduledoc false
  use Ecto.Schema

  schema "users" do
    field(:email, :string)
    field(:encrypted_password, :string, redact: true)
    field(:failed_attempts, :integer, default: 0)
    field(:locked_at, :utc_datetime_usec)
    field(:unlock_token, :string, redact: true)
    field(:remember_created_at, :utc_datetime_usec)
    field(:deleted_at, :utc_datetime_usec)
    field(:otp_required_for_login, :boolean, default: false)
    field(:provider, :string)
    field(:status, :integer)
    field(:sign_in_count, :integer, default: 0)
    field(:current_sign_in_at, :utc_datetime_usec)
    field(:last_sign_in_at, :utc_datetime_usec)
    field(:current_sign_in_ip, :string)
    field(:last_sign_in_ip, :string)
    field(:updated_at, :utc_datetime_usec)
  end
end
