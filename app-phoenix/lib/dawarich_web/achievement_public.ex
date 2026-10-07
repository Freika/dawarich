defmodule DawarichWeb.AchievementPublic do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Achievements.{PublicCard, UiText}
  alias Dawarich.Auth.Admission
  alias DawarichWeb.{Locale, RailsAuth, RailsCsrf, RailsProxy, RailsSession}

  @markers ~w(client aff via referral invitation_token pending_import_ticket dawarich_client)
  @headers ~w(turbo-frame x-http-method-override x-dawarich-client content-type transfer-encoding)
  @path ~r|\A/shared/achievements/([^/.]{1,100})\z|

  def init(opts), do: opts
  def open?(conn, _params), do: eligible?(conn)

  def eligible?(conn) do
    conn.method in ~w(GET HEAD) and conn.request_path =~ @path and
      Admission.headers(conn.req_headers) == :ok and
      Enum.all?(@headers, &(get_req_header(conn, &1) == [])) and
      get_req_header(conn, "content-length") in [[], ["0"]] and
      not Enum.any?(conn.req_headers, fn {name, _} -> String.contains?(name, "_") end) and
      DawarichWeb.Strangler.page_request?(conn)
  end

  def load(conn, opts \\ []) do
    conn = RailsAuth.call(conn, [])

    with true <- eligible?(conn),
         {:ok, params} <-
           DawarichWeb.AchievementPublicQuery.decode(conn.query_string, ~w(locale embed)),
         true <- not Map.has_key?(params, "locale") or params["locale"] in Locale.locales(),
         true <- session?(conn),
         [_, uuid] <- Regex.run(@path, conn.request_path),
         result when result != :handoff <-
           PublicCard.load(Keyword.get(opts, :repo, Dawarich.Repo), uuid, %{
             viewer_id: conn.assigns.current_user && conn.assigns.current_user.id,
             requested_locale: params["locale"]
           }),
         true <- representable?(conn, params, result) do
      {:ok, %{conn | params: params, query_params: params}, result}
    else
      _ -> {:handoff, conn}
    end
  rescue
    _ -> {:handoff, conn}
  end

  def call(conn, opts) do
    case load(conn, opts) do
      {:ok, conn, result} -> assign(conn, :achievement_public, result)
      {:handoff, conn} -> handoff(conn, opts)
    end
  end

  def handoff(conn, opts) do
    if Dawarich.Standalone.enabled?() do
      DawarichWeb.StandaloneError.respond(conn, "achievement_public")
    else
      upstream =
        Keyword.get_lazy(opts, :upstream, fn ->
          Application.fetch_env!(:dawarich, :rails_upstream)
        end)

      conn |> RailsProxy.call(upstream) |> halt()
    end
  end

  defp session?(conn) do
    session = conn.assigns.rails_session
    csrf = session["_csrf_token"]

    csrf? =
      is_nil(csrf) or
        (is_binary(csrf) and
           match?({:ok, <<_::binary-size(32)>>}, Base.url_decode64(csrf, padding: false)))

    warden? =
      not Map.has_key?(session, "warden.user.user.key") or not is_nil(conn.assigns.current_user)

    flash? =
      case session["flash"] do
        nil ->
          true

        %{"flashes" => flashes, "discard" => discard} ->
          is_map(flashes) and is_list(discard) and
            Enum.all?(flashes, fn {key, value} -> is_binary(key) and is_binary(value) end)

        _ ->
          false
      end

    csrf? and warden? and flash? and not Enum.any?(@markers, &Map.has_key?(session, &1))
  end

  defp representable?(conn, params, result) do
    changes = if params["locale"], do: %{"locale" => params["locale"]}, else: %{}

    changes =
      if result == :not_found do
        locale =
          Locale.resolve(params["locale"], conn.assigns.current_user, conn.assigns.rails_session)

        Map.put(changes, "flash", %{
          "discard" => [],
          "flashes" => %{"alert" => UiText.t(locale, "public.not_found")}
        })
      else
        if params["embed"] == "1",
          do: changes,
          else:
            Map.put(
              changes,
              "_csrf_token",
              conn.assigns.rails_session["_csrf_token"] || RailsCsrf.new_token()
            )
      end

    RailsSession.rewrite(conn.cookies["_dawarich_session"], changes, Dawarich.RailsSecret.fetch())
    true
  end
end
