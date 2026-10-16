defmodule DawarichWeb.InsightsRoutes do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Accounts.Scope

  def init(opts), do: opts

  def call(conn, opts) do
    year = conn.path_params["year"] |> String.replace_suffix(".json", "")

    if Regex.match?(~r/\A[0-9]{4}\z/, year),
      do: respond(%{conn | path_params: Map.put(conn.path_params, "year", year)}, opts),
      else: conn |> send_resp(404, "") |> halt()
  end

  defp respond(conn, _opts) do
    with %{id: _} = user <- conn.assigns[:current_user],
         {:ok, result} <-
           Dawarich.Insights.YearRoutes.fetch(
             Scope.for_user(user, conn.assigns[:locale] || "en"),
             conn.path_params["year"],
             now: conn.assigns[:now] || DateTime.utc_now(),
             self_hosted:
               Map.get(
                 conn.assigns,
                 :self_hosted,
                 Dawarich.ReleaseMigration.self_hosted?(System.get_env())
               )
           ) do
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("cache-control", "private, no-store")
      |> send_resp(200, Jason.encode!(result))
    else
      nil -> conn |> put_resp_header("location", "/users/sign_in") |> send_resp(302, "") |> halt()
      {:error, :invalid_input} -> conn |> send_resp(422, "") |> halt()
      _ -> conn |> send_resp(401, "") |> halt()
    end
  end
end
