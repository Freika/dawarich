defmodule Dawarich.GeocodingFixtures do
  @moduledoc false

  alias Dawarich.ActiveRecordEncryption

  @keys %{
    "OTP_ENCRYPTION_PRIMARY_KEY" => "schema-parity-primary-key",
    "OTP_ENCRYPTION_DETERMINISTIC_KEY" => "schema-parity-deterministic-key",
    "OTP_ENCRYPTION_KEY_DERIVATION_SALT" => "schema-parity-key-derivation-salt"
  }

  def create_tables(_context) do
    Dawarich.ScratchCase.scratch_sql!("""
    CREATE TABLE users (id bigserial PRIMARY KEY, email varchar NOT NULL, admin boolean DEFAULT false, deleted_at timestamp(6));
    CREATE TABLE service_settings (id bigserial PRIMARY KEY, user_id bigint NOT NULL REFERENCES users (id), service integer NOT NULL, provider varchar NOT NULL, config jsonb DEFAULT '{}' NOT NULL, credentials text, active boolean DEFAULT FALSE NOT NULL, created_at timestamp(6) NOT NULL, updated_at timestamp(6) NOT NULL);
    CREATE UNIQUE INDEX ON service_settings (user_id, service, provider);
    CREATE UNIQUE INDEX ON service_settings (user_id, service) WHERE active;
    CREATE TABLE instance_settings (id bigserial PRIMARY KEY, key varchar NOT NULL, value jsonb, encrypted_value text, created_at timestamp(6) NOT NULL, updated_at timestamp(6) NOT NULL);
    CREATE UNIQUE INDEX ON instance_settings (key);
    """)

    :ok
  end

  def env(extra \\ %{}), do: Map.merge(@keys, extra)

  def key, do: elem(ActiveRecordEncryption.key(@keys), 1)

  def encrypted(plaintext), do: ActiveRecordEncryption.encrypt(plaintext, key())

  def flipped_tag(plaintext) do
    message = plaintext |> encrypted() |> Jason.decode!()
    <<first, rest::binary>> = Base.decode64!(message["h"]["at"])

    Jason.encode!(
      put_in(message, ["h", "at"], Base.encode64(<<Bitwise.bxor(first, 1), rest::binary>>))
    )
  end

  def string_headers, do: ~s({"p":"","h":"headers"})

  def user(email, opts \\ []) do
    %{rows: [[id]]} =
      Dawarich.ScratchRepo.query!(
        "INSERT INTO users (email, admin, deleted_at) VALUES ($1, $2, $3) RETURNING id",
        [email, Keyword.get(opts, :admin, false), if(opts[:deleted], do: ~N[2026-01-01 00:00:00])]
      )

    id
  end

  def setting(user_id, provider, config, opts \\ []) do
    Dawarich.ScratchRepo.query!(
      "INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at) " <>
        "VALUES ($1, 0, $2, $3, $4, $5, '2026-01-01', '2026-01-01')",
      [user_id, provider, config, opts[:credentials], Keyword.get(opts, :active, false)]
    )
  end

  def settings do
    Dawarich.ScratchRepo.query!(
      "SELECT user_id, provider, config, credentials, active FROM service_settings ORDER BY id"
    ).rows
    |> Enum.map(fn [user_id, provider, config, credentials, active] ->
      {user_id, provider, config, plaintext(credentials), active}
    end)
  end

  def instance_settings do
    Dawarich.ScratchRepo.query!(
      "SELECT key, value, encrypted_value FROM instance_settings ORDER BY id"
    ).rows
    |> Enum.map(fn
      [key, value, nil] -> {key, value}
      [key, nil, secret] -> {key, {:secret, plaintext(secret)}}
    end)
  end

  def plaintext(nil), do: nil

  def plaintext(ciphertext) do
    case ActiveRecordEncryption.decrypt(ciphertext, key()) do
      {:ok, text} -> text
      {:error, _reason} -> {:unreadable, ciphertext}
    end
  end

  def with_env(vars, fun) do
    saved = Map.new(vars, fn {name, _value} -> {name, System.get_env(name)} end)
    Enum.each(vars, fn {name, value} -> System.put_env(name, value) end)

    try do
      fun.()
    after
      Enum.each(saved, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end
  end
end
