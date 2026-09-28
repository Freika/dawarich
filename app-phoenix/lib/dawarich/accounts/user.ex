defmodule Dawarich.Accounts.User do
  @moduledoc false
  use Ecto.Schema

  @schema_prefix "public"

  schema "users" do
    field :email, :string
    field :encrypted_password, :string, redact: true
    field :remember_created_at, :utc_datetime_usec
    field :locked_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec
    field :theme, :string
    field :settings, :map
    field :admin, :boolean
  end
end
