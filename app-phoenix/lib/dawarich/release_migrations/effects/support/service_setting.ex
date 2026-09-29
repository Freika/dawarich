defmodule Dawarich.ReleaseMigrations.Effects.Support.ServiceSetting do
  @moduledoc false

  alias Dawarich.ActiveRecordEncryption
  alias Dawarich.ActiveRecordEncryption.Message
  alias Dawarich.ReleaseMigrations.Effects.Support.{GeocodingSchema, Ruby}

  @chain ~w[photon geoapify nominatim locationiq]
  @columns "id, user_id, provider, config, credentials"
  @decryption_error "ActiveRecord::Encryption::Errors::Decryption"
  @unknown_zlib_error "Zlib::DataError (zlib's message is not available in Phoenix)"

  def chain, do: @chain

  def new(user_id, provider, config, api_key) do
    plaintext =
      if Ruby.present?(api_key),
        do: encode({:object, [{"api_key", Ruby.strip(api_key)}]})

    %{
      id: nil,
      user_id: user_id,
      provider: provider,
      config: config,
      stored: nil,
      credentials: {:assigned, plaintext}
    }
  end

  def find_by(repo, user_id, provider) do
    repo.query!(
      "SELECT #{@columns} FROM service_settings WHERE user_id = $1 AND service = 0 AND provider = $2 LIMIT 1",
      [user_id, provider],
      log: false
    ).rows
    |> Enum.map(&loaded/1)
    |> List.first()
  end

  def active_geocoding(repo) do
    repo.query!(
      "SELECT #{@columns} FROM service_settings WHERE service = 0 AND active = TRUE AND user_id IN (SELECT id FROM users WHERE deleted_at IS NULL)",
      [],
      log: false
    ).rows
    |> Enum.map(&loaded/1)
  end

  def credentials(%{credentials: {:assigned, plaintext}}, _key), do: {:ok, plaintext}
  def credentials(%{stored: nil}, _key), do: {:ok, nil}
  def credentials(%{stored: ciphertext}, key), do: decrypt(ciphertext, key)

  def api_key(setting, key), do: setting |> credentials_hash(key) |> Ruby.index("api_key")

  def drop_api_key(setting, key) do
    remaining =
      case credentials_hash(setting, key) do
        {:object, pairs} -> {:object, Enum.reject(pairs, &(elem(&1, 0) == "api_key"))}
        list when is_list(list) -> Enum.reject(list, &(&1 == "api_key"))
        string when is_binary(string) -> string
        other -> Ruby.no_method!("delete", other)
      end

    plaintext = if remaining in [{:object, []}, [], ""], do: nil, else: encode(remaining)
    %{setting | credentials: {:assigned, plaintext}}
  end

  def insert!(repo, setting, key) do
    repo.query!(
      "INSERT INTO service_settings (user_id, service, provider, config, credentials, active, created_at, updated_at) " <>
        "VALUES ($1, 0, $2, $3::text::jsonb, $4, FALSE, now(), now())",
      [setting.user_id, setting.provider, encode(setting.config), encrypt(setting, key)],
      log: false
    )
  end

  def activate!(repo, setting, key) do
    repo.query!("SELECT 1 FROM users WHERE id = $1 FOR UPDATE", [setting.user_id], log: false)

    repo.query!(
      "UPDATE service_settings SET active = FALSE WHERE user_id = $1 AND service = 0 AND id <> $2",
      [setting.user_id, setting.id],
      log: false
    )

    restore = rollback_error(setting, key)

    try do
      saved = GeocodingSchema.normalize(setting, key)
      GeocodingSchema.validate!(saved, key)
      {sets, params} = changes(setting, saved, key)

      repo.query!(
        "UPDATE service_settings SET #{Enum.join(["active = TRUE", "updated_at = now()" | sets], ", ")} WHERE id = $1",
        [setting.id | params],
        log: false
      )
    rescue
      error in [Ruby.Error, Postgrex.Error] ->
        reraise(if(restore, do: %Ruby.Error{message: restore}, else: error), __STACKTRACE__)
    end
  end

  def rollback_error(%{stored: nil}, _key), do: nil
  def rollback_error(_setting, {:error, message}), do: message

  def rollback_error(%{stored: ciphertext}, key) do
    case decrypt(ciphertext, key) do
      {:ok, _plaintext} -> nil
      :unreadable -> @decryption_error
    end
  rescue
    error in Ruby.Error -> error.message
  end

  def key!({:ok, key}), do: key
  def key!({:error, message}), do: raise(Ruby.Error, message)

  defp changes(loaded, saved, key) do
    config =
      if saved.config == loaded.config,
        do: [],
        else: [{"config", "::text::jsonb", encode(saved.config)}]

    credentials =
      case saved.credentials do
        {:assigned, plaintext} ->
          if original(loaded, key) == plaintext,
            do: [],
            else: [{"credentials", "", encrypt(saved, key)}]

        :stored ->
          []
      end

    (config ++ credentials)
    |> Enum.with_index(2)
    |> Enum.map(fn {{column, cast, value}, index} -> {"#{column} = $#{index}#{cast}", value} end)
    |> Enum.unzip()
  end

  defp original(%{stored: nil}, _key), do: nil

  defp original(%{stored: ciphertext}, key) do
    case decrypt(ciphertext, key) do
      {:ok, plaintext} -> plaintext
      :unreadable -> raise Ruby.Error, @decryption_error
    end
  end

  defp decrypt(ciphertext, key) do
    case ActiveRecordEncryption.decrypt(ciphertext, key!(key)) do
      {:ok, plaintext} -> {:ok, plaintext}
      {:error, {:rescued, _reason}} -> :unreadable
      {:error, {:raised, _class, nil}} -> raise Ruby.Error, @unknown_zlib_error
      {:error, {:raised, _class, message}} -> raise Ruby.Error, message
      {:error, {:unreproducible, message}} -> raise Ruby.Unreproducible, message
    end
  end

  defp encrypt(%{credentials: {:assigned, nil}}, _key), do: nil

  defp encrypt(%{credentials: {:assigned, plaintext}}, key),
    do: ActiveRecordEncryption.encrypt(plaintext, key!(key))

  defp credentials_hash(setting, key) do
    case credentials(setting, key) do
      {:ok, plaintext} when is_binary(plaintext) ->
        if Ruby.blank?(plaintext), do: {:object, []}, else: parse(plaintext)

      _nil_or_unreadable ->
        {:object, []}
    end
  end

  defp parse(plaintext) do
    case Message.decode_json(plaintext) do
      {:ok, term} -> term
      {:error, {:rescued, _reason}} -> {:object, []}
      {:error, {:unreproducible, message}} -> raise Ruby.Unreproducible, message
    end
  end

  defp loaded([id, user_id, provider, config, stored]) do
    %{
      id: id,
      user_id: user_id,
      provider: provider,
      config: config,
      stored: stored,
      credentials: :stored
    }
  end

  defp encode(term), do: IO.iodata_to_binary(Ruby.json(term))
end
