defmodule DawarichWeb.StandaloneError do
  @moduledoc false
  import Plug.Conn
  require Logger

  def respond(conn, reason \\ "unsupported_envelope", status \\ 422) do
    metadata = %{method: conn.method, path: conn.request_path, reason: reason, status: status}
    Logger.warning("[standalone.handback] " <> Jason.encode!(metadata))

    method =
      if conn.method in ~w(GET HEAD POST PUT PATCH DELETE OPTIONS), do: conn.method, else: "OTHER"

    :telemetry.execute([:dawarich, :standalone, :handback], %{count: 1}, %{
      metadata
      | method: method
    })

    message =
      if status == 422, do: "Unprocessable Entity", else: Plug.Conn.Status.reason_phrase(status)

    {type, body} =
      if json?(conn) do
        {"application/json", Jason.encode!(%{error: message})}
      else
        html = DawarichWeb.ErrorHTML.render("#{status}.html", %{})
        {"text/html", html |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()}
      end

    conn
    |> put_resp_content_type(type)
    |> send_resp(status, if(conn.method == "HEAD", do: "", else: body))
    |> halt()
  end

  defp json?(conn),
    do:
      String.starts_with?(conn.request_path, "/api/") or
        Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "application/json"))
end
