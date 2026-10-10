defmodule DawarichWeb.AdminWrites.Request do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.Auth.{ActionCsrf, Admission}
  alias DawarichWeb.{AdminWritesGate, Locale, RailsAuth, RailsProxy, RequestURL}

  @common ~w(authenticity_token commit utf8 _method)
  @background "settings[visits_suggestions_enabled]"

  def load(conn, action, opts \\ []) do
    context = AdminWritesGate.context(opts)

    if AdminWritesGate.eligible?(conn, action, opts) and transport?(conn) do
      conn = RailsAuth.call(conn, AdminWritesGate.auth_options(context))

      case read_all(conn, []) do
        {:ok, raw, conn} ->
          conn = put_private(conn, :dawarich_raw_body, raw)
          parse(conn, raw, action, context)

        {:error, conn} ->
          {:handoff, conn |> send_resp(400, "") |> halt()}
      end
    else
      {:handoff, conn}
    end
  end

  def refresh_actor(conn, action, context) do
    conn = RailsAuth.call(conn, AdminWritesGate.auth_options(context))

    if AdminWritesGate.eligible?(conn, action, context: context),
      do: {:ok, conn.assigns.current_user},
      else: {:handoff, :actor}
  end

  defp parse(conn, raw, action, context) do
    with {:ok, params} <- Admission.form(raw, conn.query_string, fields(action), options(action)),
         true <- required_group?(params, action),
         {:ok, method} <- method(conn.method, action, params),
         true <- csrf?(conn, params, method),
         {:ok, actor} <- refresh_actor(conn, action, context) do
      context =
        context
        |> Map.put(:method, method)
        |> Map.put(:action, action)
        |> Map.put(
          :form_order,
          raw |> URI.query_decoder() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
        )
        |> Map.put(:locale, Locale.resolve(nil, actor, conn.assigns.rails_session))

      {:ok, conn, actor, Map.delete(params, "_method"), context}
    else
      _ -> {:handoff, conn}
    end
  end

  defp required_group?(params, :background),
    do: Map.has_key?(params, @background) or Map.has_key?(params, "job_name")

  defp transport?(conn) do
    with [length] <- get_req_header(conn, "content-length"),
         true <- length =~ ~r/\A\d+\z/ and String.to_integer(length) <= 65_536,
         [type] <- get_req_header(conn, "content-type"),
         true <- hd(String.split(type, ";")) == "application/x-www-form-urlencoded",
         [] <- get_req_header(conn, "transfer-encoding"),
         do: true,
         else: (_ -> false)
  end

  defp fields(:background), do: @common ++ [@background, "job_name"]

  defp options(:background),
    do: [
      query_fields: %{
        @background => ["true", "false"],
        "job_name" => Dawarich.Admin.BackgroundCommands.names()
      }
    ]

  defp method("POST", :background, %{"job_name" => _} = params),
    do: if(Map.has_key?(params, "_method"), do: :handoff, else: {:ok, "POST"})

  defp method("POST", _action, %{"_method" => "patch"}), do: {:ok, "PATCH"}

  defp method("PATCH", _action, params),
    do: if(Map.has_key?(params, "_method"), do: :handoff, else: {:ok, "PATCH"})

  defp method(_, _, _), do: :handoff

  defp csrf?(conn, params, method) do
    tokens =
      Enum.reject(
        [params["authenticity_token"] | get_req_header(conn, "x-csrf-token")],
        &is_nil/1
      )

    get_req_header(conn, "origin") in [[], [RequestURL.base(conn)]] and
      length(get_req_header(conn, "x-csrf-token")) <= 1 and
      Enum.any?(
        tokens,
        &ActionCsrf.valid?(conn.assigns.rails_session, &1, method, conn.request_path)
      )
  end

  defp read_all(%{private: %{dawarich_raw_body: raw}} = conn, []) when is_binary(raw),
    do: {:ok, raw, conn}

  defp read_all(conn, acc) do
    case read_body(conn, RailsProxy.read_options()) do
      {:more, raw, conn} -> read_all(conn, [acc, raw])
      {:ok, raw, conn} -> {:ok, IO.iodata_to_binary([acc, raw]), conn}
      {:error, _} -> {:error, conn}
    end
  end
end
