defmodule Dawarich.ReleaseMigrations.Effects.CopyRegistrationSetting do
  @moduledoc false

  alias Dawarich.RailsCache.{Marshal, Wire}
  alias Dawarich.Redis

  def run(repo, opts \\ []) do
    case registration(repo) do
      [[value]] -> {:ok, value}
      [] -> copy(repo, opts)
    end
  rescue
    _ -> {:error, :registration_copy_refused}
  catch
    _ -> {:error, :registration_copy_refused}
  end

  defp copy(repo, opts) do
    env = Keyword.get(opts, :env, System.get_env())

    with {:ok, bytes} <- read(opts),
         {:ok, value} <- decode(bytes, env) do
      repo.transaction(fn ->
        repo.query!(
          "INSERT INTO phoenix.registration_setting (id, enabled) VALUES (true, $1) " <>
            "ON CONFLICT (id) DO NOTHING",
          [value],
          log: false
        )

        [[winner]] = registration(repo)
        winner
      end)
    else
      _ -> {:error, :registration_copy_refused}
    end
  end

  defp read(opts) do
    args = ["GET", "dawarich/registration_enabled"]

    case opts[:command] do
      command when is_function(command, 1) -> command.(args)
      nil -> read_cache(args, opts)
    end
  end

  defp read_cache(args, opts) do
    {:ok, _} = Application.ensure_all_started(:redix)
    config = Application.fetch_env!(:dawarich, :redis)
    url = Keyword.fetch!(config, :url)

    options =
      url
      |> Redis.options(config[:cache_database])
      |> Keyword.delete(:name)
      |> Keyword.put(:sync_connect, true)

    {:ok, conn} = Redix.start_link(url, options)

    try do
      command = Keyword.get(opts, :cache_command, &Redis.command/2)
      command.(args, conn)
    after
      Redix.stop(conn)
    end
  end

  defp registration(repo),
    do:
      repo.query!("SELECT enabled FROM phoenix.registration_setting WHERE id = true", [],
        log: false
      ).rows

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
