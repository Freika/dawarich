defmodule Dawarich.Settings do
  @moduledoc false

  alias Dawarich.Accounts.Scope
  alias Dawarich.{Accounts, Jobs, Repo}
  alias Dawarich.Auth.ApiKeys
  alias Dawarich.Mail.TestEmail
  alias Dawarich.Settings.{General, Supporter}
  alias Dawarich.Visits.WebSettings

  def update_general(%Scope{user: user}, params) do
    case General.save(Repo, user.id, params) do
      {:ok, settings} -> {:ok, settings}
      {:error, :save_failed} -> {:error, :save_failed}
      {:error, _} -> {:error, :invalid}
    end
  end

  def update_visits(%Scope{user: user}, params, now \\ DateTime.utc_now()) do
    case WebSettings.save(Jobs.repo(), user.id, params, now) do
      {:ok, saved} -> {:ok, saved}
      {:replay, reason} -> raise "visit settings could not be saved: #{reason}"
    end
  end

  def request_visit_redetection(%Scope{user: user, locale: locale}, now \\ DateTime.utc_now()) do
    case WebSettings.redetect(Jobs.repo(), user.id, now, locale) do
      {:ok, _} -> :ok
      {:cooldown, 429} -> :cooldown
      {:cooldown, 429, :native} -> :cooldown
      {:replay, reason} -> raise "visit redetection could not be queued: #{reason}"
    end
  end

  def verify_supporter(%Scope{user: user}, params, now \\ DateTime.utc_now()),
    do: Supporter.verify(Repo, user.id, params, now)

  def send_test_email(%Scope{user: user, locale: locale}, opts \\ []) do
    env = Keyword.get_lazy(opts, :env, &System.get_env/0)
    self_hosted = Keyword.get_lazy(opts, :self_hosted, &self_hosted?/0)
    actor = Accounts.get(user.id)

    if self_hosted do
      TestEmail.run(actor, locale, env, Keyword.take(opts, [:oban, :clock]))
    else
      {:ok, text} =
        Dawarich.I18n.t(
          locale,
          "controllers.application.you_are_not_authorized_to_perform_this_action"
        )

      {:alert, text}
    end
  end

  def rotate_api_key(%Scope{user: user}, session_salt) do
    case ApiKeys.rotate(user.id, session_salt, %{native: true}) do
      {:ok, updated} -> {:ok, updated}
      {:handoff, _} -> {:error, :stale_session}
    end
  end

  defp self_hosted?, do: System.get_env("SELF_HOSTED") == "true"
end
