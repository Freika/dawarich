defmodule Dawarich.Auth.Providers.Completion do
  @moduledoc false
  alias Dawarich.Auth.{
    Account,
    Trackable,
    RegistrationAttribution,
    RegistrationPolicy,
    SessionCookie
  }

  alias Dawarich.Auth.Providers.{Accounts, Failure, OidcAccounts}
  alias Dawarich.{Repo, RailsSecret}
  alias DawarichWeb.AuthCookie
  import Ecto.Query

  def run(conn, provider, exchange, context) do
    with {:ok, identity} <- exchange.(),
         {:ok, user, created} <- resolve(identity, provider, context) do
      if user,
        do: complete(conn, user, created, provider, context),
        else: Failure.respond(conn, :registration_disabled, provider, context)
    else
      {:link_required, link} -> challenge(conn, link, provider, context)
      {:error, reason} -> Failure.respond(conn, reason, provider, context)
    end
  rescue
    _ ->
      :telemetry.execute([:dawarich, :auth, :provider, :failure], %{count: 1}, %{
        reason: :completion_failed
      })

      Failure.terminal(conn)
  end

  def complete(conn, user, created, provider, context) do
    if Dawarich.Accounts.unlocked?(user, clock(context)),
      do: finish(conn, user, created, provider, context),
      else: Failure.redirect(conn, "/users/sign_in", "devise.failure.locked", %{}, context)
  end

  defp finish(conn, user, created, provider, context) do
    repo = Map.get(context, :repo, Repo)
    session = client_session(conn)

    session =
      if created and context[:self_hosted] == false,
        do: signup(repo, user, session, context),
        else: session

    {:ok, {user, session}} =
      repo.transaction(fn ->
        user =
          repo.one!(from(u in Account, where: u.id == ^user.id, lock: "FOR UPDATE"), log: false)

        changes = Trackable.changes(user, clock(context), Map.get(context, :ip, "127.0.0.1"))

        user =
          repo.update!(
            Ecto.Changeset.change(
              user,
              changes |> Map.put(:failed_attempts, 0) |> Map.put(:updated_at, clock(context))
            ),
            log: false
          )

        {user, claim(repo, user, session, context)}
      end)

    path = destination(user, session, context, conn)

    notice =
      DawarichWeb.Translate.t(
        Map.get(context, :locale, "en"),
        "devise.omniauth_callbacks.success",
        %{"kind" => Accounts.label(provider, context)}
      )

    conn
    |> AuthCookie.session(
      SessionCookie.for_login(
        session,
        user,
        notice,
        Map.get_lazy(context, :secret, &RailsSecret.fetch/0)
      )
    )
    |> Failure.redirect_to(path)
  end

  def claim(repo, user, session, context) do
    case Map.pop(session, "pending_import_ticket") do
      {nil, session} ->
        session

      {ticket, session} ->
        user = %{user | settings: Dawarich.Accounts.settings(user.id)}
        Dawarich.PendingImports.Claim.claim(repo, user, ticket, %{now: clock(context)})
        session
    end
  end

  def client_session(conn, params \\ %{}) do
    session = conn.assigns.rails_session
    client = List.first(Plug.Conn.get_req_header(conn, "x-dawarich-client")) || params["client"]

    if client in ["ios", "android"],
      do: Map.put(session, "dawarich_client", client),
      else: session
  end

  defp destination(user, session, context, conn) do
    client =
      List.first(Plug.Conn.get_req_header(conn, "x-dawarich-client")) ||
        session["dawarich_client"]

    invitation = RegistrationPolicy.invitation(session["invitation_token"], context)

    cond do
      invitation && invitation.acceptable ->
        "/family/invitations/" <> URI.encode_www_form(session["invitation_token"])

      user.status == 3 ->
        "/trial/resume"

      client in ["ios", "android"] ->
        case context[:mobile_redirect] do
          fun when is_function(fun, 2) ->
            case fun.(user, client) do
              {:ok, "/" <> rest = path} ->
                if safe_path?(path, rest),
                  do: path,
                  else: raise(ArgumentError, "Invalid mobile destination")

              _ ->
                raise(ArgumentError, "Mobile handoff unavailable")
            end

          _ ->
            raise(ArgumentError, "Mobile handoff unavailable")
        end

      true ->
        local_destination(session["user_return_to"])
    end
  end

  defp signup(repo, user, session, context) do
    callback = get_in(context, [:callbacks, :webhook])

    if not is_function(callback, 1) or callback.(user.id) != :ok,
      do: raise(ArgumentError, "Signup callback unavailable")

    {:ok, session} =
      repo.transaction(fn -> RegistrationAttribution.apply(repo, user, %{}, session, context) end)

    session
  end

  defp challenge(conn, link, provider, context) do
    pending = %{
      "user_id" => link.user.id,
      "provider" => link.provider,
      "uid" => link.uid,
      "provider_label" => Accounts.label(provider, context),
      "expires_at" => DateTime.to_unix(clock(context)) + 900
    }

    session = Map.put(conn.assigns.rails_session, "pending_oauth_link", pending)

    conn
    |> AuthCookie.session(
      SessionCookie.for_form(session, Map.get_lazy(context, :secret, &RailsSecret.fetch/0))
    )
    |> Failure.redirect_to("/auth/account_link/challenge")
  end

  defp resolve(identity, "openid_connect", context),
    do: OidcAccounts.resolve(identity, Map.put(context, :on_email_collision, :raise_only))

  defp resolve(identity, _, context),
    do: Accounts.resolve(identity, Map.put(context, :on_email_collision, :raise_only))

  defp local_destination("/" <> rest = path), do: if(safe_path?(path, rest), do: path, else: "/")
  defp local_destination(_), do: "/"

  defp safe_path?(path, rest),
    do:
      not String.starts_with?(rest, "/") and
        not String.contains?(path, ["\\", "\r", "\n", "\t", <<0>>])

  defp clock(context), do: Map.get(context, :clock, &DateTime.utc_now/0).()
end
