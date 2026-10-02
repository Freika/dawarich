defmodule DawarichWeb.RailsFormTest do
  use Dawarich.IngestCase, async: false

  import Bitwise
  import Plug.Conn
  import Plug.Test

  alias Dawarich.Accounts
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{RailsCsrf, RailsForm}

  setup do
    RailsUser.insert!(%{id: 7311, email: "a7s2-form@dawarich.test"})
    session = RailsUser.session(7311)
    %{session: session, token: RailsCsrf.masked_token(session)}
  end

  defp resolved_user(session) do
    case Accounts.from_session(session, DateTime.utc_now()) do
      %Accounts.User{} = user -> user
      _ -> nil
    end
  end

  defp admission(session, params, headers \\ [], query \\ %{}, current_user \\ :resolve) do
    user = if current_user == :resolve, do: resolved_user(session), else: current_user

    %{conn(:post, "/exports") | req_headers: headers}
    |> assign(:api_params, params)
    |> assign(:api_query, query)
    |> assign(:rails_session, session)
    |> assign(:current_user, user)
    |> RailsForm.admission()
  end

  defp flip_unused_bit(token) do
    alphabet = ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    {prefix, last} = String.split_at(token, -1)
    <<code::utf8>> = last
    index = Enum.find_index(alphabet, &(&1 == code))
    prefix <> <<Enum.at(alphabet, bxor(index, 1))::utf8>>
  end

  test "the page's token as X-CSRF-Token or authenticity_token admits a session sign-in", ctx do
    assert admission(ctx.session, %{}, [{"x-csrf-token", ctx.token}]) == :ok
    assert admission(ctx.session, %{"authenticity_token" => ctx.token}) == :ok

    assert admission(ctx.session, %{"authenticity_token" => "x"}, [{"x-csrf-token", ctx.token}]) ==
             :ok
  end

  test "an Origin other than this site, null or repeated goes to Rails", ctx do
    headers = fn origin -> [{"x-csrf-token", ctx.token}, {"origin", origin}] end
    assert admission(ctx.session, %{}, headers.("http://www.example.com")) == :ok

    for origin <- [
          "http://evil.test",
          "null",
          "https://www.example.com",
          "http://www.example.com:3000"
        ] do
      assert admission(ctx.session, %{}, headers.(origin)) == {:replay, "origin"}, origin
    end

    twice = [{"origin", "http://www.example.com"} | headers.("http://www.example.com")]
    assert admission(ctx.session, %{}, twice) == {:replay, "origin"}
  end

  test "a token Phoenix cannot verify goes to Rails, which decides", ctx do
    other = RailsCsrf.masked_token(RailsUser.session(7311))

    for token <- [
          String.reverse(ctx.token),
          other,
          ctx.session["_csrf_token"],
          "",
          "%%%",
          flip_unused_bit(ctx.token)
        ] do
      assert admission(ctx.session, %{}, [{"x-csrf-token", token}]) ==
               {:replay, "authenticity token"},
             token
    end

    assert admission(ctx.session, %{}) == {:replay, "authenticity token"}

    assert admission(ctx.session, %{"authenticity_token" => [ctx.token]}) ==
             {:replay, "authenticity token"}

    assert admission(Map.delete(ctx.session, "_csrf_token"), %{}, [{"x-csrf-token", ctx.token}]) ==
             {:replay, "authenticity token"}
  end

  test "only a live session sign-in is admitted", ctx do
    header = [{"x-csrf-token", ctx.token}]

    assert admission(Map.delete(ctx.session, "warden.user.user.key"), %{}, header) ==
             {:replay, "not signed in by session"}

    Repo.query!("UPDATE users SET locked_at = now() WHERE id = 7311")
    assert admission(ctx.session, %{}, header) == {:replay, "not signed in by session"}
    Repo.query!("UPDATE users SET locked_at = NULL, deleted_at = now() WHERE id = 7311")
    assert admission(ctx.session, %{}, header) == {:replay, "not signed in by session"}
  end

  test "what makes Rails write the session goes to Rails", ctx do
    header = [{"x-csrf-token", ctx.token}]

    for key <- ~w(locale client aff via), value <- ["de", "ios", ""] do
      assert admission(ctx.session, %{key => value}, header) ==
               {:replay, "session-writing parameter"},
             key
    end

    assert admission(ctx.session, %{}, [{"x-dawarich-client", "ios"} | header]) ==
             {:replay, "session-writing parameter"}
  end

  test "a method override other than POST goes to Rails", ctx do
    header = [{"x-csrf-token", ctx.token}]
    assert admission(ctx.session, %{"_method" => "post"}, header) == :ok
    assert admission(ctx.session, %{"_method" => "POST"}, header) == :ok

    for value <- ["delete", "PATCH", "get", "bogus", ["post"]] do
      assert admission(ctx.session, %{"_method" => value}, header) ==
               {:replay, "method override"},
             inspect(value)
    end

    assert admission(ctx.session, %{}, [{"x-http-method-override", "DELETE"} | header]) ==
             {:replay, "method override"}
  end

  test "headers Rack would read differently go to Rails", ctx do
    assert admission(ctx.session, %{}, [{"x_csrf_token", ctx.token}]) ==
             {:replay, "ambiguous headers"}

    assert admission(ctx.session, %{}, [{"x-csrf-token", ctx.token}, {"x-csrf-token", ctx.token}]) ==
             {:replay, "ambiguous headers"}

    assert admission(ctx.session, %{}, [
             {"x-csrf-token", ctx.token},
             {"cookie", "a=1"},
             {"cookie", "b=2"}
           ]) ==
             {:replay, "ambiguous headers"}
  end

  test "a method override present in the query, not just the body, still goes to Rails", ctx do
    header = [{"x-csrf-token", ctx.token}]

    assert admission(ctx.session, %{"_method" => "post"}, header, %{"_method" => "post"}) ==
             {:replay, "method override"}

    assert admission(ctx.session, %{}, header, %{"_method" => "anything"}) ==
             {:replay, "method override"}
  end

  test "a JSON body goes to Rails", ctx do
    headers = [
      {"content-type", "application/json"},
      {"content-length", "2"},
      {"x-csrf-token", ctx.token}
    ]

    assert admission(ctx.session, %{}, headers) == {:replay, "content type"}
  end

  test "a user RailsAuth resolved as nil is refused even though a fresh session lookup would now succeed",
       ctx do
    header = [{"x-csrf-token", ctx.token}]

    assert admission(ctx.session, %{}, header, %{}, nil) == {:replay, "not signed in by session"}
  end
end
