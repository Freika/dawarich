defmodule DawarichWeb.AchievementActions.Request do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.Auth.{ActionCsrf, Admission}
  alias DawarichWeb.{Locale, RailsProxy, RequestURL}
  alias DawarichWeb.AchievementActions.Gate

  @limit 65_536
  @common ~w(authenticity_token _method locale)

  def init(opts), do: opts

  def call(conn, opts) do
    action =
      Enum.find([:sharing, :next, :seen, :dismiss], &match?({:ok, _}, Gate.route(conn, &1)))

    case load(conn, action, opts) do
      {:ok, conn, actor, params, context} ->
        if DawarichWeb.AchievementActions.Response.supported?(conn) do
          conn
          |> Map.put(:params, params)
          |> assign(:achievement_action, {actor, params, context})
        else
          handoff(conn, opts)
        end

      {:handoff, %{halted: true} = conn} ->
        conn

      {:handoff, conn} ->
        handoff(conn, opts)
    end
  end

  def load(conn, action, opts \\ []) do
    context = Gate.context(opts)

    if Gate.eligible?(conn, action, opts) and transport?(conn) do
      case read_all(conn, []) do
        {:ok, raw, conn} ->
          conn =
            conn
            |> put_private(:dawarich_raw_body, raw)
            |> put_private(:dawarich_original_method, conn.method)

          parse(conn, raw, action, context)

        {:error, conn} ->
          {:handoff, conn |> send_resp(400, "") |> halt()}
      end
    else
      {:handoff, conn}
    end
  end

  defp parse(conn, raw, action, context) do
    kind = kind(conn)

    with true <- byte_size(raw) <= @limit and String.valid?(raw),
         {:ok, body} <- decode(raw, action, kind),
         {:ok, query} <-
           Admission.form("", conn.query_string, [],
             query_fields: %{"locale" => Locale.locales()}
           ),
         true <- Enum.all?(Map.keys(query), &(not Map.has_key?(body, &1))),
         params <- Map.merge(body, query),
         true <- locale?(params),
         {:ok, method} <- method(conn.method, action, kind, params),
         {:ok, conn, actor} <- Gate.actor(conn, context),
         true <- csrf?(conn, params, method),
         {:ok, route} <- Gate.route(conn, action),
         {:ok, context} <- Gate.snapshot(actor, action, route, params, context) do
      context =
        context
        |> Map.put(:method, method)
        |> Map.put(:action, action)
        |> Map.put(:locale, Locale.resolve(params["locale"], actor, conn.assigns.rails_session))

      {:ok, conn, actor, Map.delete(params, "_method"), context}
    else
      _ -> {:handoff, conn}
    end
  end

  defp transport?(conn) do
    with [length] <- get_req_header(conn, "content-length"),
         true <- length =~ ~r/\A\d+\z/ and String.to_integer(length) <= @limit,
         true <- kind(conn) in [:form, :json],
         [] <- get_req_header(conn, "transfer-encoding"),
         do: true,
         else: (_ -> false)
  end

  defp kind(conn) do
    case get_req_header(conn, "content-type") do
      [type] ->
        case type |> String.split(";") |> hd() |> String.trim() do
          "application/json" -> :json
          "application/x-www-form-urlencoded" -> :form
          _ -> :unsupported
        end

      _ ->
        :unsupported
    end
  end

  defp fields(:sharing), do: ["enabled"]
  defp fields(:next), do: ~w(claim_token batch_end_id)
  defp fields(:seen), do: ["claim_token"]
  defp fields(:dismiss), do: ["batch_end_id"]

  defp decode(raw, action, :form), do: Admission.form(raw, "", @common ++ fields(action))

  defp decode(raw, action, :json) do
    with {:ok, %Jason.OrderedObject{values: pairs}} <-
           Jason.decode(raw, objects: :ordered_objects),
         keys <- Enum.map(pairs, &elem(&1, 0)),
         true <- length(keys) == length(Enum.uniq(keys)),
         true <-
           Enum.all?(pairs, fn {key, value} ->
             key in ["locale" | fields(action)] and scalar?(value)
           end) do
      {:ok, Map.new(pairs)}
    else
      _ -> :handoff
    end
  end

  defp scalar?(value),
    do: is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value)

  defp locale?(params),
    do: not Map.has_key?(params, "locale") or params["locale"] in Locale.locales()

  defp method("POST", :sharing, :form, %{"_method" => "patch"}), do: {:ok, "PATCH"}

  defp method("PATCH", :sharing, _, params),
    do: if(Map.has_key?(params, "_method"), do: :handoff, else: {:ok, "PATCH"})

  defp method("POST", action, _, params) when action in [:next, :seen, :dismiss],
    do: if(Map.has_key?(params, "_method"), do: :handoff, else: {:ok, "POST"})

  defp method(_, _, _, _), do: :handoff

  defp csrf?(conn, params, method) do
    tokens =
      Enum.reject(
        [params["authenticity_token"] | get_req_header(conn, "x-csrf-token")],
        &is_nil/1
      )

    get_req_header(conn, "origin") in [[], [RequestURL.base(conn)]] and length(tokens) == 1 and
      ActionCsrf.valid?(conn.assigns.rails_session, hd(tokens), method, conn.request_path)
  end

  defp read_all(conn, acc) do
    case read_body(conn, RailsProxy.read_options()) do
      {:more, raw, conn} -> read_all(conn, [acc, raw])
      {:ok, raw, conn} -> {:ok, IO.iodata_to_binary([acc, raw]), conn}
      {:error, _} -> {:error, conn}
    end
  end

  defp handoff(conn, opts), do: DawarichWeb.AchievementActions.Gate.refuse(conn, opts)
end
