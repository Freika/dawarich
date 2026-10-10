defmodule DawarichWeb.NativeAuthChromeTest do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  alias Dawarich.Test.{RailsFormRequests, RailsUser}
  alias DawarichWeb.RailsCsrf

  setup do
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    env = %{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true", "FORCE_SSL" => "false"}
    previous = Map.new(env, fn {name, _} -> {name, System.get_env(name)} end)
    System.put_env(env)

    on_exit(fn ->
      for {name, value} <- previous,
          do: if(value, do: System.put_env(name, value), else: System.delete_env(name))
    end)

    Dawarich.State.put_registration_enabled(Repo, true)

    user =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "http-chrome@example.test",
        api_key: "synthetic-chrome-key",
        settings: %{}
      })

    %{session: RailsUser.session(user.id)}
  end

  defp render(fun, attrs) do
    apply(DawarichWeb.AuthHttpChrome, fun, [Map.put(attrs, :__changed__, nil)])
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  test "HTTP sign-out serializes effective DELETE and valid action CSRF", c do
    token = RailsCsrf.masked_form_token(c.session, "/users/sign_out", "DELETE")
    html = render(:sign_out, %{locale: "en", rails_csrf_token: token})
    dom = LazyHTML.from_fragment(html)

    fields =
      for node <- LazyHTML.query(dom, "input[name]"), into: %{} do
        {[name], [value]} = {LazyHTML.attribute(node, "name"), LazyHTML.attribute(node, "value")}
        {name, value}
      end

    assert fields["_method"] == "delete"

    assert Dawarich.Auth.ActionCsrf.valid?(
             c.session,
             fields["authenticity_token"],
             "DELETE",
             "/users/sign_out"
           )

    response =
      RailsFormRequests.post_form(c.session, URI.encode_query(fields), [], "/users/sign_out")

    assert response.status == 303
    assert get_resp_header(response, "location") == ["http://www.example.com/"]
    refute Map.has_key?(RailsFormRequests.rails_session(response), "warden.user.user.key")
  end

  test "HTTP settings tabs retain active item and visible keyboard focus" do
    html =
      render(:settings_navigation, %{
        locale: "de",
        active: "two_factor",
        self_hosted: true,
        admin: false,
        two_factor: true
      })

    dom = LazyHTML.from_fragment(html)
    selected = LazyHTML.query(dom, "a[aria-current=page]")
    assert LazyHTML.attribute(selected, "href") == ["/settings/two_factor"]

    for node <- LazyHTML.query(dom, "a") do
      assert Enum.any?(LazyHTML.attribute(node, "class"), &String.contains?(&1, "focus-visible"))
    end

    refute html =~ "phx-hook"
    refute html =~ "RailsStimulus"
  end
end
