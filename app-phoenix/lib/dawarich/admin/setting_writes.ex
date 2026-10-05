defmodule Dawarich.Admin.SettingWrites do
  @moduledoc false
  alias Dawarich.Auth.RegistrationSetting
  alias Dawarich.Auth.Recovery.Settings
  alias Dawarich.{Repo, UserSettings}

  def registration(actor, params, context) do
    repo = Map.get(context, :repo, Repo)

    with {:ok, _} <- actor(actor, repo, context, true) do
      value = UserSettings.cast(params["registration_enabled"])

      case RegistrationSetting.put(value, repo) do
        :ok -> {:ok, value}
        _ -> {:terminal, :cache}
      end
    end
  end

  def background(actor, params, context) do
    repo = Map.get(context, :repo, Repo)

    with {:ok, raw} <- actor(actor, repo, context, false),
         {:ok, settings} <- sanitize(raw, params, context) do
      now = Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_naive()

      result =
        repo.query!(
          "UPDATE users SET settings=$1,updated_at=$2 WHERE id=$3",
          [settings, now, actor.id],
          log: false
        )

      if result.num_rows == 1, do: {:ok, actor.id}, else: {:terminal, :actor}
    end
  end

  defp actor(actor, repo, context, admin?) do
    cond do
      context[:self_hosted] != true ->
        {:handoff, :cloud}

      context[:oidc] == true ->
        {:handoff, :oidc}

      true ->
        case repo.query!(
               "SELECT admin,settings FROM users WHERE id=$1 AND deleted_at IS NULL",
               [actor.id],
               log: false
             ).rows do
          [[admin, settings]] when not admin? or admin == true -> {:ok, settings}
          _ -> {:handoff, :actor}
        end
    end
  end

  defp sanitize(raw, params, context) do
    settings =
      UserSettings.safe(raw, Map.get(context, :env, System.get_env()))
      |> Map.merge(Map.take(params, ["visits_suggestions_enabled"]))

    case Settings.sanitize(settings) do
      {:ok, settings} ->
        previous = if is_map(raw), do: raw["timezone"], else: nil

        if previous == settings["timezone"],
          do: {:ok, settings},
          else: {:handoff, :timezone_callback}

      _ ->
        {:handoff, :settings_callback}
    end
  end
end
