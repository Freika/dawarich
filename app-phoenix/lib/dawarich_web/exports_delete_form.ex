defmodule DawarichWeb.ExportsDeleteForm do
  @moduledoc false
  @behaviour Plug
  alias DawarichWeb.{RailsForm, Api.Body}

  def init(opts), do: opts

  def call(conn, _opts) do
    override = conn.assigns.api_params["_method"]

    cond do
      ambiguous?(conn) ->
        Body.replay(conn, "export delete method")

      conn.method == "POST" and (not is_binary(override) or String.upcase(override) != "DELETE") ->
        Body.replay(conn, "export delete method")

      conn.method == "DELETE" and not is_nil(override) ->
        Body.replay(conn, "export delete method")

      true ->
        case RailsForm.admission(conn, allowed_overrides: ["DELETE"]) do
          :ok -> conn
          {:replay, reason} -> Body.replay(conn, reason)
        end
    end
  end

  defp ambiguous?(conn) do
    case Body.segments(conn.private[:dawarich_raw_body] || "") do
      {:ok, pairs} -> Enum.count(pairs, fn {key, _} -> key == "_method" end) > 1
      _ -> true
    end
  end
end
