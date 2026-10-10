defmodule Dawarich.Exports.LegacyPurgeWorker do
  @moduledoc false
  use Oban.Worker, queue: :exports, max_attempts: 26

  def path(url) when is_binary(url) do
    path = url |> String.trim() |> String.trim_leading("/")

    if path != "" and not String.contains?(path, ["\\", "\0", ":", "?", "#"]) and
         Enum.all?(String.split(path, "/"), &(&1 not in ["", ".", ".."])) do
      {:ok, path}
    else
      {:error, :unsafe_legacy_path}
    end
  end

  def path(_), do: {:error, :unsafe_legacy_path}

  def enqueue!(repo, url) do
    {:ok, path} = path(url)
    repo.insert!(new(%{"path" => path}), prefix: "oban", log: false)
    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, %{"path" => path}, opts \\ []) do
    if repo.in_transaction?(),
      do: raise(ArgumentError, "legacy purge requires a committed deletion")

    root =
      Keyword.get_lazy(opts, :root, fn ->
        Application.get_env(:dawarich, :public_root) || Dawarich.RailsRoot.join("public")
      end)

    with {:ok, safe} <- path(path),
         :ok <- parents(root, safe) do
      if repo.query!("SELECT 1 FROM exports WHERE ltrim(btrim(url),'/')=$1 LIMIT 1", [safe],
           log: false
         ).rows == [] do
        case File.rm(Path.join(root, safe)) do
          :ok -> :ok
          {:error, :enoent} -> :ok
          {:error, reason} -> {:error, reason}
        end
      else
        :ok
      end
    end
  end

  defp parents(root, path) do
    path
    |> Path.split()
    |> Enum.drop(-1)
    |> Enum.reduce_while(root, fn segment, parent ->
      next = Path.join(parent, segment)

      case File.lstat(next) do
        {:ok, %{type: :symlink}} -> {:halt, {:error, :unsafe_legacy_path}}
        {:ok, %{type: :directory}} -> {:cont, next}
        {:error, :enoent} -> {:halt, :ok}
        _ -> {:halt, {:error, :unsafe_legacy_path}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      _ -> :ok
    end
  end
end
