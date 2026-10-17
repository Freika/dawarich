defmodule Dawarich.Settings.Supporter do
  @moduledoc false
  alias Dawarich.{Jobs, Settings.General, Supporters, UserSettings}

  @installs "app_store_supporter_installs"
  @ruby_space ~r/\A[\x00\t\n\v\f\r ]+|[\x00\t\n\v\f\r ]+\z/

  def flag(settings, value, install) do
    case install_id(install) do
      nil ->
        Map.put(settings, "app_store_supporter", value)

      id ->
        installs = settings[@installs] |> ruby_array() |> Enum.reject(&(&1 == id))

        installs =
          if UserSettings.cast(value) in [nil, false], do: installs, else: installs ++ [id]

        settings |> Map.put(@installs, installs) |> Map.put("app_store_supporter", installs != [])
    end
  end

  defp install_id(raw) when is_binary(raw) do
    id = String.replace(raw, @ruby_space, "")
    if id != "" and length(String.codepoints(id)) <= 128, do: id
  end

  defp install_id(_raw), do: nil

  defp ruby_array(nil), do: []
  defp ruby_array(list) when is_list(list), do: list
  defp ruby_array(map) when is_map(map), do: Enum.map(map, fn {key, value} -> [key, value] end)
  defp ruby_array(value), do: [value]

  def verify(repo, id, params, now \\ DateTime.utc_now()) do
    with {:ok, email} <- normalized(params["supporter_email"], true),
         {:ok, github} <- normalized(params["supporter_github_username"], false),
         false <- email == "" and github == "" do
      changes =
        %{} |> present("supporter_email", email) |> present("supporter_github_username", github)

      with {:ok, settings} <- General.save(repo, id, changes) do
        invalidate(email, github)
        {:ok, Supporters.info(Map.delete(settings, "app_store_supporter"), now)}
      end
    else
      true -> {:error, :empty}
      _ -> {:error, :invalid}
    end
  end

  defp normalized(nil, _), do: {:ok, ""}

  defp normalized(value, downcase) when is_binary(value) do
    value = String.trim(value)
    {:ok, if(downcase, do: String.downcase(value), else: value)}
  end

  defp normalized(_, _), do: {:error, :invalid}
  defp present(changes, _, ""), do: changes
  defp present(changes, key, value), do: Map.put(changes, key, value)

  defp invalidate(email, github) do
    keys = []

    keys =
      if email != "",
        do: [
          "dawarich/supporter:" <> Base.encode16(:crypto.hash(:sha256, email), case: :lower)
          | keys
        ],
        else: keys

    keys =
      if github != "",
        do: ["dawarich/supporter_gh:" <> String.downcase(github) | keys],
        else: keys

    Jobs.repo().query!("DELETE FROM phoenix.supporter_checks WHERE cache_key=ANY($1)", [keys],
      log: false
    )
  end
end
