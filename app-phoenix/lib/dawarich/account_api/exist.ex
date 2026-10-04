defmodule Dawarich.AccountApi.Exist do
  @moduledoc false

  alias Dawarich.{I18n, Repo}
  alias Dawarich.Ingest.Ruby

  @integer ~r/\A[\x09-\x0D ]*([+-]?[0-9]+(?:_[0-9]+)*)[\x09-\x0D ]*\z/

  def run(params, provided, env \\ System.get_env()) do
    secret = env["SUBSCRIPTION_WEBHOOK_SECRET"]

    cond do
      Ruby.blank?(secret) -> error(503, "configuration_error")
      not Plug.Crypto.secure_compare(provided, secret) -> error(401, "invalid_webhook_secret")
      is_nil(params["ids"]) -> error(422, "ids_is_required")
      true -> query(params["ids"])
    end
  end

  defp query(raw) do
    raw = if is_list(raw), do: raw, else: [raw]

    if length(raw) <= 4096 and Enum.all?(raw, &Ruby.scalar?/1) do
      ids = raw |> Enum.flat_map(&integer/1) |> Enum.uniq()

      bounded =
        Enum.filter(ids, &(&1 >= -9_223_372_036_854_775_808 and &1 <= 9_223_372_036_854_775_807))

      existing =
        Repo.query!("SELECT id FROM users WHERE id=ANY($1) AND deleted_at IS NULL", [
          bounded
        ]).rows
        |> List.flatten()

      {:ok, 200, {:object, [{"existing", existing}, {"missing", ids -- existing}]}}
    else
      {:replay, "manager ids shape"}
    end
  end

  defp integer(raw) do
    case Regex.run(@integer, Ruby.to_s(raw), capture: :all_but_first) do
      [text] -> [text |> String.replace("_", "") |> String.to_integer()]
      nil -> []
    end
  end

  defp error(status, key),
    do: {:ok, status, {:object, [{"error", I18n.en!("controllers.api.v1.users." <> key)}]}}
end
