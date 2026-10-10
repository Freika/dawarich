defmodule Dawarich.Accounts.User do
  @moduledoc false
  use Ecto.Schema

  @schema_prefix "public"

  schema "users" do
    field(:first_name, :string)
    field(:last_name, :string)
    field :email, :string
    field :provider, :string
    field :encrypted_password, :string, redact: true
    field :remember_created_at, :utc_datetime_usec
    field :locked_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec
    field :theme, :string
    field :settings, :map, redact: true
    field :admin, :boolean
    field :status, :integer
    field :plan, :integer
    field :active_until, :utc_datetime_usec
    field :subscription_source, :integer
    field :changelog_consent, :integer
    field :api_key, :string, redact: true
    field :points_count, :integer
  end
end
