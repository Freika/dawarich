defmodule Dawarich.ReleaseMigrations.Effects.CopyRegistrationSetting do
  @moduledoc false

  alias Dawarich.RailsCache.{Marshal, Wire}

  def run(repo, opts \\ []) do
    env = Keyword.get(opts, :env, System.get_env())
    command = Keyword.fetch!(opts, :command)

    with {:ok, bytes} <- command.(["GET", "dawarich/registration_enabled"]),
         {:ok, value} <- decode(bytes, env) do
      repo.query!(
        "INSERT INTO phoenix.registration_setting (id, enabled) VALUES (true, $1) " <>
          "ON CONFLICT (id) DO NOTHING",
        [value],
        log: false
      )

      %{rows: [[winner]]} =
        repo.query!("SELECT enabled FROM phoenix.registration_setting WHERE id = true", [],
          log: false
        )

      {:ok, winner}
    else
      _ -> {:error, :registration_copy_refused}
    end
  rescue
    _ -> {:error, :registration_copy_refused}
  catch
    _ -> {:error, :registration_copy_refused}
  end

  defp decode(nil, env), do: {:ok, env["ALLOW_EMAIL_PASSWORD_REGISTRATION"] == "true"}

  defp decode(bytes, _env) do
    with :ok <- metadata(bytes),
         {:ok, %{value: value}} <- Wire.decode(bytes),
         true <- value in [true, false, nil],
         do: {:ok, value}
  end

  defp metadata(<<0, 17, _type, expires::little-float-64, -1::little-signed-32, _::binary>>)
       when expires < 0,
       do: :ok

  defp metadata(<<0, 17, _::binary>>), do: :error
  defp metadata(<<0, payload::binary>>), do: legacy_metadata(payload)
  defp metadata(<<1, payload::binary>>), do: legacy_metadata(:zlib.uncompress(payload))
  defp metadata(_), do: :error

  defp legacy_metadata(payload) do
    with {:ok, packed} when is_list(packed) and length(packed) <= 3 <- Marshal.decode(payload),
         nil <- Enum.at(packed, 1),
         nil <- Enum.at(packed, 2),
         do: :ok
  end
end
