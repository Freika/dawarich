defmodule Dawarich.AfterCommit.Visibility do
  @moduledoc false

  def record(repo, operation, payload) do
    user = payload["user_id"]
    keys = if user, do: [user_key(user)], else: []
    keys = keys ++ Enum.map(payload["keys"] || [], &key_id/1)

    keys =
      if operation in ["subscription", "rate_limit"] do
        hash = payload["key_hash"] || api_hash(repo, user)
        if hash, do: ["cache:plan:" <> hash | keys], else: keys
      else
        keys
      end

    if keys != [], do: Dawarich.State.bump_epochs(repo, keys)
    :ok
  end

  def generation(repo, user), do: token(repo, [user_key(user)])

  def key(repo, key) do
    if String.contains?(key, "/phoenix-generation/") do
      key
    else
      keys = [key_id(key)] ++ user_keys(key)

      case token(repo, keys) do
        "" -> key
        token -> key <> "/phoenix-generation/" <> token
      end
    end
  end

  def user_key?(key), do: user_keys(key) != []

  def plan(repo, key), do: token(repo, ["cache:plan:" <> hash(key)])

  defp token(repo, keys) do
    repo.query!("SELECT token FROM phoenix.epochs WHERE key=ANY($1::text[]) ORDER BY key", [keys],
      log: false
    ).rows
    |> List.flatten()
    |> Enum.join("-")
  end

  defp user_keys(key) do
    case Regex.run(
           ~r{(?:dawarich/user_|insights/yearly_digest/|timeline_month_summary/)(\d+)},
           key
         ) do
      [_, id] ->
        [user_key(id)]

      _ ->
        case Regex.run(~r{views/.+?/(\d+)/insights/}, key) do
          [_, id] -> [user_key(id)]
          _ -> []
        end
    end
  end

  defp api_hash(repo, user) do
    case repo.query!("SELECT api_key FROM users WHERE id=$1", [user], log: false).rows do
      [[key]] when is_binary(key) -> hash(key)
      _ -> nil
    end
  end

  defp user_key(user), do: "cache:user:#{user}"
  defp key_id(key), do: "cache:key:" <> hash(key)
  defp hash(key), do: Base.encode16(:crypto.hash(:sha256, key), case: :lower)
end
