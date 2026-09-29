defmodule Dawarich.Supporters do
  @moduledoc false

  alias Dawarich.{AppVersion, Http, Jobs}

  @url "https://verify.dawarich.app/api/v1/verify"
  @ttl 24 * 60 * 60
  @false_values [false, 0, "0", "f", "F", "false", "FALSE", "off", "OFF"]

  def badge?(settings, now), do: badge?(settings, now, AppVersion.current())

  def badge?(settings, now, running_version) when is_map(settings),
    do: show?(settings["show_supporter_badge"]) and supporter?(settings, now, running_version)

  def badge?(_settings, _now, _running_version), do: false

  defp show?(nil), do: true
  defp show?(""), do: false
  defp show?(value), do: value not in @false_values

  defp supporter?(settings, now, running_version) do
    email = present(settings["supporter_email"])
    github = present(settings["supporter_github_username"])

    cond do
      email && by_email(email, now, running_version) -> true
      github -> by_github(github, now, running_version)
      true -> false
    end
  end

  defp present(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp present(_value), do: nil

  defp by_email(raw, now, running_version) do
    email = raw |> String.downcase() |> String.trim()
    hash = Base.encode16(:crypto.hash(:sha256, email), case: :lower)

    email != "" and
      check("dawarich/supporter:" <> hash, "email_hash=" <> hash, now, running_version)
  end

  defp by_github(raw, now, running_version) do
    name = raw |> String.trim() |> String.downcase()

    name != "" and
      check(
        "dawarich/supporter_gh:" <> name,
        "github_username=" <> URI.encode_www_form(name),
        now,
        running_version
      )
  end

  defp check(key, query, now, running_version) do
    result =
      case Jobs.repo().query!(
             "SELECT result FROM phoenix.supporter_checks WHERE cache_key = $1 AND checked_at > $2",
             [key, DateTime.add(now, -@ttl)]
           ) do
        %{rows: [[cached]]} -> cached
        _ -> tap(fetch(query, running_version), &store(key, &1, now))
      end

    result["supporter"] == true
  end

  defp fetch(query, running_version) do
    url = Application.get_env(:dawarich, :supporter_verify_url, @url) <> "?" <> query

    with {:ok, status, body} when status in 200..299 <-
           Http.get(url, [{"x-dawarich-version", running_version}]),
         {:ok, %{} = result} <- Jason.decode(body) do
      result
    else
      _ -> %{"supporter" => false}
    end
  end

  defp store(key, result, now) do
    Jobs.repo().query!(
      "INSERT INTO phoenix.supporter_checks (cache_key, result, checked_at) VALUES ($1, $2, $3) ON CONFLICT (cache_key) DO UPDATE SET result = EXCLUDED.result, checked_at = EXCLUDED.checked_at",
      [key, result, now]
    )
  end
end
