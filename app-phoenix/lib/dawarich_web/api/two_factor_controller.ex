defmodule DawarichWeb.Api.TwoFactorController do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.Auth.TwoFactor.Api
  alias DawarichWeb.Api.{Body, Respond}

  def init(action), do: action

  def call(conn, action) do
    result =
      if supported?(conn) do
        context = %{self_hosted: true}

        context =
          if conn.assigns[:api_now],
            do: Map.put(context, :clock, fn -> conn.assigns.api_now end),
            else: context

        Api.run(action, conn.assigns.api_user.id, conn.assigns.api_params, context)
      else
        {:replay, :two_factor_input}
      end

    case result do
      {:ok, status, term} -> Respond.json(conn, status, term)
      {:replay, reason} -> Body.replay(conn, reason)
    end
  end

  defp supported?(conn) do
    conn.assigns.api_format in [:json, :html, :all] and
      not Map.has_key?(conn.assigns.api_params, "_method") and
      Enum.all?(conn.assigns.api_params, fn {_key, value} -> is_nil(value) or is_binary(value) end) and
      unique_pairs?(conn.query_string) and unique_body?(conn)
  end

  defp unique_body?(conn) do
    raw = conn.private[:dawarich_raw_body] || ""

    case Body.kind(conn) do
      :none ->
        true

      :form ->
        unique_pairs?(raw)

      :json when raw == "" ->
        true

      :json ->
        case Jason.decode(raw, objects: :ordered_objects) do
          {:ok, %Jason.OrderedObject{values: pairs}} -> unique?(pairs)
          _ -> false
        end

      _ ->
        false
    end
  end

  defp unique_pairs?(raw) do
    case Body.segments(raw) do
      {:ok, pairs} -> unique?(pairs)
      _ -> false
    end
  end

  defp unique?(pairs) do
    keys = Enum.map(pairs, &elem(&1, 0))
    length(keys) == length(Enum.uniq(keys))
  end
end
