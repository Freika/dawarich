defmodule Dawarich.AppVersion.CheckWorker do
  @moduledoc false
  use Oban.Worker, queue: :app_version_checking, max_attempts: 1

  alias Dawarich.Jobs.Ownership

  @key "cron:app_version_checking_job"
  @url "https://api.github.com/repos/Freika/dawarich/tags"
  @release ~r/\A\d+\.\d+\.\d+\z/

  @impl Oban.Worker
  def perform(_job) do
    if rails_env() == "production" do
      :ok
    else
      case fetch(Application.get_env(:dawarich, :app_version_url, @url)) do
        {:ok, version} -> store(version)
        :error -> :ok
      end
    end
  end

  defp rails_env, do: System.get_env("RAILS_ENV") || System.get_env("RACK_ENV") || "development"

  defp fetch(url) do
    with {:ok, status, body} when status in 200..299 <-
           Dawarich.Http.get(url, [{"user-agent", "Dawarich"}, {"accept", "application/json"}]),
         {:ok, tags} when is_list(tags) <- Jason.decode(body) do
      {:ok, Enum.find_value(tags, Dawarich.AppVersion.current(), &release_name/1)}
    else
      _ -> :error
    end
  end

  defp release_name(%{"name" => name}) when is_binary(name), do: if(name =~ @release, do: name)
  defp release_name(_tag), do: nil

  defp store(version) do
    repo = Dawarich.Jobs.repo()

    case Ownership.with_owner(repo, @key, :oban, fn ->
           repo.query!(
             """
             INSERT INTO phoenix.app_version (id, latest_version, checked_at) VALUES (true, $1, $2)
             ON CONFLICT (id) DO UPDATE SET latest_version = EXCLUDED.latest_version, checked_at = EXCLUDED.checked_at
             """,
             [version, DateTime.utc_now()],
             log: false
           )
         end) do
      {:ok, _} -> :ok
      {:skip, _owner} -> {:cancel, :not_owner}
    end
  end
end
