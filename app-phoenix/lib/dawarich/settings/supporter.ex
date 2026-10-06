defmodule Dawarich.Settings.Supporter do
  @moduledoc false
  alias Dawarich.{Jobs, Settings.General, Supporters}

  def verify(repo, id, params, now \\ DateTime.utc_now()) do
    with {:ok, email} <- normalized(params["supporter_email"], true),
         {:ok, github} <- normalized(params["supporter_github_username"], false),
         false <- email == "" and github == "" do
      changes =
        %{} |> present("supporter_email", email) |> present("supporter_github_username", github)

      with {:ok, settings} <- General.save(repo, id, changes) do
        invalidate(email, github)
        {:ok, Supporters.info(settings, now)}
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
