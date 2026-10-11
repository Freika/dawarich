defmodule DawarichWeb.AuthMobile.Success do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.{RequestURL, Translate}
  def init(opts), do: opts

  def route?(conn),
    do: conn.method in ["GET", "HEAD"] and conn.request_path == "/auth/ios/success"

  def call(conn, opts) do
    context = Keyword.get(opts, :context, %{})
    conn = fetch_query_params(conn)
    locale = Map.get(context, :locale, "en")

    if conn.query_params["token"] not in [nil, ""] do
      body =
        Translate.t(
          locale,
          "controllers.auth.ios.authentication_successful_you_can_close_this_window",
          %{}
        )

      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, if(conn.method == "HEAD", do: "", else: body))
      |> halt()
    else
      body =
        Jason.encode!(%{
          success: true,
          message: Translate.t(locale, "controllers.auth.ios.ios_authentication_successful", %{}),
          redirect_url: RequestURL.base(conn) <> "/"
        })

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, if(conn.method == "HEAD", do: "", else: body))
      |> halt()
    end
  end
end
