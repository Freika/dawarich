defmodule DawarichWeb.TestEmail do
  @moduledoc false
  @behaviour Plug
  require EEx
  import Plug.Conn

  alias Dawarich.Auth.{ActionCsrf, Admission}
  alias Dawarich.Mail

  alias DawarichWeb.{
    Locale,
    RailsAuth,
    RailsHeaders,
    RailsProxy,
    RailsSession,
    RequestURL,
    TestEmailGate
  }

  @template Path.expand("../../priv/mail/residual/test_email_flash.html.eex", __DIR__)
  @external_resource @template
  EEx.function_from_file(:defp, :flash_body, @template, [:assigns])

  defp icon(:notice),
    do:
      ~s|<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewbox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class="size-6"><circle cx="12" cy="12" r="10"></circle><path d="m9 12 2 2 4-4"></path></svg>|

  defp icon(:alert),
    do:
      ~s|<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewbox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class="size-6"><circle cx="12" cy="12" r="10"></circle><path d="m15 9-6 6"></path><path d="m9 9 6 6"></path></svg>|

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    context = TestEmailGate.context(opts)

    cond do
      TestEmailGate.non_admin?(conn) ->
        conn
        |> put_resp_header("x-dawarich-mail-owner", "native-test-email")
        |> send_resp(403, "")
        |> halt()

      Dawarich.Standalone.enabled?() and not context.self_hosted and conn.method == "POST" and
          conn.request_path == "/settings/general/test_email" ->
        with true <- transport?(conn),
             {:ok, raw, conn} <- read_all(conn, []),
             {:ok, params} <-
               Admission.form(raw, conn.query_string, ~w(authenticity_token commit utf8 _method)),
             conn = RailsAuth.call(conn, []),
             true <- params["_method"] in [nil, "post", "POST"],
             true <- csrf?(conn, params) do
          cloud_refusal(conn)
        else
          _ -> DawarichWeb.SettingsActions.reject(conn, 422)
        end

      true ->
        dispatch(conn, opts)
    end
  end

  defp dispatch(conn, opts) do
    case admit(conn, opts) do
      {:ok, conn, actor, locale, format, context} ->
        native(conn, actor, locale, format, context, opts)

      {:handoff, %{halted: true} = conn} ->
        conn

      {:handoff, conn} ->
        if Dawarich.Standalone.enabled?(),
          do: DawarichWeb.SettingsActions.reject(conn, 422),
          else:
            conn |> RailsProxy.call(Application.fetch_env!(:dawarich, :rails_upstream)) |> halt()
    end
  end

  defp cloud_refusal(conn) do
    conn = RailsAuth.call(conn, [])

    if conn.assigns.current_user do
      locale = Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)

      message =
        DawarichWeb.Translate.t(
          locale,
          "controllers.application.you_are_not_authorized_to_perform_this_action",
          %{}
        )

      conn
      |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => %{"alert" => message}}})
      |> put_resp_header("location", RequestURL.base(conn) <> "/")
      |> send_resp(303, "")
      |> halt()
    else
      DawarichWeb.SettingsActions.reject(conn, 302)
    end
  end

  def admit(conn, opts \\ []) do
    if TestEmailGate.eligible?(conn, opts) and transport?(conn) do
      conn = RailsAuth.call(conn, [])

      with {:ok, raw, conn} <- read_all(conn, []) do
        conn = put_private(conn, :dawarich_raw_body, raw)

        with {:ok, params} <-
               Admission.form(raw, conn.query_string, ~w(authenticity_token commit utf8 _method)),
             true <- params["_method"] in [nil, "post", "POST"],
             true <- csrf?(conn, params) do
          context = TestEmailGate.context(opts)
          actor = conn.assigns.current_user

          {:ok, conn, actor, Locale.resolve(nil, actor, conn.assigns.rails_session),
           TestEmailGate.format(conn), context}
        else
          _ -> {:handoff, conn}
        end
      end
    else
      {:handoff, conn}
    end
  end

  defp native(conn, actor, locale, format, context, opts) do
    {kind, message} = Mail.TestEmail.run(actor, locale, context.env, opts)
    conn = put_resp_header(conn, "x-dawarich-mail-owner", "native-test-email")

    if format == :turbo do
      {:ok, close} = Dawarich.I18n.t(locale, "shared.flash_message.close")

      assigns = %{
        timeout: if(kind == :notice, do: 5000, else: 0),
        class: if(kind == :notice, do: "alert-success", else: "alert-error"),
        icon: icon(kind),
        message: Mail.ExploreFeatures.h(message),
        close: Mail.ExploreFeatures.h(close)
      }

      conn
      |> RailsHeaders.call([])
      |> put_resp_content_type("text/vnd.turbo-stream.html")
      |> send_resp(200, flash_body(assigns))
      |> halt()
    else
      flash = %{"discard" => [], "flashes" => %{to_string(kind) => message}}

      conn
      |> RailsSession.stage(%{"flash" => flash})
      |> RailsHeaders.call([])
      |> put_resp_content_type("text/html")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("location", RequestURL.base(conn) <> "/settings/general")
      |> send_resp(302, "")
      |> halt()
    end
  rescue
    _ ->
      conn
      |> put_resp_header("x-dawarich-mail-owner", "native-test-email")
      |> RailsHeaders.call([])
      |> send_resp(500, "")
      |> halt()
  end

  defp csrf?(conn, params) do
    tokens =
      Enum.reject(
        [params["authenticity_token"] | get_req_header(conn, "x-csrf-token")],
        &is_nil/1
      )

    get_req_header(conn, "origin") in [[], [RequestURL.base(conn)]] and length(tokens) == 1 and
      ActionCsrf.valid?(conn.assigns.rails_session, hd(tokens), "POST", conn.request_path)
  end

  defp transport?(conn) do
    with [length] <- get_req_header(conn, "content-length"),
         true <- length =~ ~r/\A\d+\z/ and String.to_integer(length) <= 65_536,
         [type] <- get_req_header(conn, "content-type"),
         true <- hd(String.split(type, ";")) == "application/x-www-form-urlencoded",
         [] <- get_req_header(conn, "transfer-encoding"),
         do: true,
         else: (_ -> false)
  end

  defp read_all(conn, acc) do
    case read_body(conn, RailsProxy.read_options()) do
      {:more, raw, conn} -> read_all(conn, [acc, raw])
      {:ok, raw, conn} -> {:ok, IO.iodata_to_binary([acc, raw]), conn}
      {:error, _} -> {:handoff, conn |> send_resp(400, "") |> halt()}
    end
  end
end
