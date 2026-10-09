defmodule Dawarich.Admin.Background do
  @moduledoc false

  alias Dawarich.Admin.{Access, BackgroundPage, JobHealth, SettingWrites}
  alias Dawarich.Imports.IntegrationCommands
  alias Dawarich.Repo

  @reverse ~w(start_reverse_geocoding continue_reverse_geocoding)
  @notice "controllers.settings.background_jobs.job_was_successfully_created"

  def page(scope, operator \\ nil) do
    with {:ok, scope} <- Access.admit(scope, :background, env: env(), operator: operator) do
      health =
        if scope.user.admin == true do
          JobHealth.load(repo(), Dawarich.Jobs.repo(), System.get_env("DAWARICH_PHOENIX_NODE"))
        end

      {:ok, Map.put(BackgroundPage.read(scope.user), :health, health)}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def update_visits(scope, params) do
    with {:ok, scope} <- Access.admit(scope, :background, write: true, env: env()) do
      case SettingWrites.background(scope.user, params, context(scope)) do
        {:ok, _} = result -> result
        {:handoff, reason} when reason in [:cloud, :oidc] -> {:error, reason}
        _ -> {:error, :unavailable}
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def request_job(scope, name, operator \\ nil) do
    with {:ok, scope} <-
           Access.admit(scope, :background, write: true, env: env(), operator: operator),
         :ok <- hosted_job(name) do
      opts = [locale: scope.locale, self_hosted: Dawarich.ReleaseMigration.self_hosted?(env())]
      opts = Keyword.put(opts, :oban, Map.get(config(), :oban, Oban))

      case IntegrationCommands.enqueue(repo(), scope.user.id, name, opts) do
        {:ok, :queued} -> {:ok, %{destination: destination(name), notice_key: @notice}}
        {:error, _} = result -> result
        _ -> {:error, :enqueue_failed}
      end
    end
  rescue
    _ -> {:error, :enqueue_failed}
  end

  defp hosted_job(name) do
    if name in @reverse and not Dawarich.ReleaseMigration.self_hosted?(env()),
      do: {:error, :cloud},
      else: :ok
  end

  defp destination("start_airtrail_import"), do: "/settings/integrations"
  defp destination("start_teslamate_sync"), do: "/settings/integrations?service=teslamate"
  defp destination(name) when name in @reverse, do: "/settings/background_jobs"
  defp destination(_), do: "/imports"

  defp context(scope) do
    Map.merge(config(), %{
      repo: repo(),
      env: env(),
      locale: scope.locale,
      self_hosted: Dawarich.ReleaseMigration.self_hosted?(env()),
      oidc: Dawarich.Auth.Admission.oidc?(env())
    })
  end

  defp config, do: Application.get_env(:dawarich, __MODULE__, %{})
  defp repo, do: Map.get(config(), :repo, Repo)
  defp env, do: Map.get(config(), :env, System.get_env())
end
