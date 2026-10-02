defmodule DawarichWeb.Api.Auth do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Dawarich.{Accounts, AppVersion, I18n, RailsCookies, RailsSecret}
  alias DawarichWeb.Api.{Body, Headers, Respond}
  alias DawarichWeb.Strangler

  @bearer ~r/\ABearer\s+(\S+)\z/i
  @accept ~r/\A([\w.+*\/-]+)(?:\s*;\s*\w+="?[\w.]+"?)*\z/
  @formats %{
    "application/json" => :json,
    "text/x-json" => :json,
    "application/jsonrequest" => :json,
    "text/html" => :html,
    "application/xhtml+xml" => :html,
    "*/*" => :all,
    "text/plain" => :text,
    "application/xml" => :xml,
    "text/xml" => :xml,
    "application/x-xml" => :xml
  }

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    conn = conn |> assign(:api_started, System.monotonic_time()) |> fetch_cookies()

    case admission(conn) do
      {:ok, format, vary, user} ->
        conn
        |> assign(:api_format, format)
        |> assign(:api_vary, vary)
        |> assign(:api_request_id, request_id(conn))
        |> assign(:api_headers, Headers.dawarich(user != nil, version()))
        |> assign(:api_if_none_match, joined(conn, "if-none-match"))
        |> admit(user, opts)

      {:replay, reason} ->
        Body.replay(conn, reason)
    end
  end

  @doc false
  def admission(conn) do
    with :ok <- headers(conn),
         :ok <- cookies(conn),
         :ok <- client(conn),
         {:ok, format, vary} <- format(conn),
         {:ok, key} <- api_key(conn),
         {:ok, user} <- lookup(key),
         do: {:ok, format, vary, user}
  end

  defp headers(conn) do
    if Enum.any?(conn.req_headers, fn {name, _value} -> String.contains?(name, "_") end) or
         length(get_req_header(conn, "cookie")) > 1,
       do: {:replay, "ambiguous headers"},
       else: :ok
  end

  @doc false
  def admit(conn, nil, _opts), do: Respond.head(conn, 401)

  def admit(conn, user, opts) do
    active? = Keyword.get(opts, :require_active, true)

    cond do
      user.status == 3 and Keyword.get(opts, :reject_pending, true) ->
        Respond.json(
          conn,
          402,
          {:object,
           [
             {"error", "payment_required"},
             {"message", t("complete_your_subscription_to_continue")},
             {"resume_url", nil}
           ]}
        )

      active? and user.status == 0 ->
        Respond.json(conn, 401, {:object, [{"error", t("user_account_is_not_active")}]})

      active? and not known_active_until?(user.active_until) ->
        Respond.head(conn, 401)

      active? and expired?(user.active_until) ->
        Respond.json(conn, 401, {:object, [{"error", t("user_subscription_is_not_active")}]})

      true ->
        assign(conn, :api_user, user)
    end
  end

  defp known_active_until?(nil), do: true
  defp known_active_until?(%NaiveDateTime{}), do: true
  defp known_active_until?(_other), do: false

  defp expired?(%NaiveDateTime{} = until),
    do: NaiveDateTime.compare(until, NaiveDateTime.utc_now()) == :lt

  defp expired?(nil), do: false

  defp cookies(%{cookies: cookies}) do
    remember? = Map.has_key?(cookies, "remember_user_token")

    case cookies["_dawarich_session"] do
      nil -> if remember?, do: {:replay, "remember-me cookie"}, else: :ok
      value -> session(value, remember?)
    end
  end

  defp session(value, remember?) do
    now = DateTime.utc_now()

    case RailsSecret.fetch() do
      nil ->
        {:replay, "no cookie secret"}

      secret ->
        case RailsCookies.decrypt(value, "_dawarich_session", secret, now) do
          {:ok, %{} = session} ->
            cond do
              Map.has_key?(session, "warden.user.user.key") ->
                if match?(%Accounts.User{}, Accounts.from_session(session, now)),
                  do: :ok,
                  else: {:replay, "stale session"}

              remember? ->
                {:replay, "remember-me cookie"}

              true ->
                :ok
            end

          _ ->
            if remember?, do: {:replay, "remember-me cookie"}, else: :ok
        end
    end
  rescue
    error -> {:replay, "session lookup failed: " <> inspect(error.__struct__)}
  end

  defp client(conn) do
    client =
      List.first(get_req_header(conn, "x-dawarich-client")) || conn.assigns.api_params["client"]

    if client in ["ios", "android"], do: {:replay, "client header writes the session"}, else: :ok
  end

  defp format(conn) do
    cond do
      Map.has_key?(conn.assigns.api_params, "format") ->
        case Map.get(
               %{
                 "json" => :json,
                 "html" => :html,
                 "xml" => :xml,
                 "text" => :text,
                 "jpg" => :jpeg
               },
               conn.assigns.api_params["format"]
             ) do
          nil -> {:replay, "format parameter"}
          format -> {:ok, format, false}
        end

      get_req_header(conn, "x-requested-with") != [] ->
        {:replay, "X-Requested-With"}

      true ->
        accept(joined(conn, "accept"))
    end
  end

  defp accept(value) do
    cond do
      String.trim(value) == "" -> {:ok, :html, false}
      Strangler.browser_like?(value) -> {:ok, :html, false}
      String.contains?(value, ",") -> {:replay, "multi-valued Accept"}
      true -> single(Regex.run(@accept, value, capture: :all_but_first))
    end
  end

  defp single([type]) when is_map_key(@formats, type), do: {:ok, @formats[type], true}
  defp single(_other), do: {:replay, "Accept type"}

  defp api_key(conn) do
    case conn.assigns.api_params["api_key"] do
      key when key in [nil, false] -> {:ok, bearer(conn)}
      key when is_binary(key) -> {:ok, key}
      key when is_integer(key) -> {:ok, Integer.to_string(key)}
      _ -> {:replay, "api_key shape"}
    end
  end

  defp bearer(conn) do
    case Regex.run(@bearer, joined(conn, "authorization"), capture: :all_but_first) do
      [token] -> token
      nil -> nil
    end
  end

  defp joined(conn, name),
    do:
      conn
      |> get_req_header(name)
      |> Enum.map_join(", ", &String.replace(&1, ~r/\A[ \t]+|[ \t]+\z/, ""))

  defp lookup(key) do
    if key in [nil, ""] or String.trim(key) == "",
      do: {:ok, nil},
      else: {:ok, Accounts.by_api_key(key)}
  rescue
    error -> {:replay, "user lookup failed: " <> inspect(error.__struct__)}
  end

  defp request_id(conn) do
    value = joined(conn, "x-request-id")

    if String.trim(value) == "",
      do: Ecto.UUID.generate(),
      else: value |> String.replace(~r/[^\w\-@]/, "") |> String.slice(0, 255)
  end

  defp version do
    with nil <- :persistent_term.get({__MODULE__, :version}, nil) do
      tap(AppVersion.current(), &:persistent_term.put({__MODULE__, :version}, &1))
    end
  end

  defp t(key), do: I18n.en!("controllers.api." <> key)
end
