defmodule DawarichWeb.SharingParityTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [get_resp_header: 2, put_req_header: 3]

  alias Dawarich.Test.{ParityHTML, SharingSeeds}

  @endpoint DawarichWeb.Endpoint
  @external_resource "test/fixtures/sharing/pages.json"
  @pages SharingSeeds.fixture("pages.json")["pages"]
  @scripts ~s(script[type="importmap"], script#i18n-translations)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    SharingSeeds.load!()
    :ok
  end

  defp request(%{"verb" => "get", "path" => path}, cookie), do: get(conn(cookie), path)

  defp request(%{"verb" => "post", "path" => path, "params" => params}, cookie) do
    body = URI.encode_query(params || %{})

    conn(cookie)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> post(path, body)
  end

  defp conn(nil), do: build_conn()
  defp conn({name, value}), do: build_conn() |> put_req_header("cookie", "#{name}=#{value}")

  defp unlocked(%{"cookie" => nil}), do: nil

  defp unlocked(%{"cookie" => name, "path" => path}) do
    unlock =
      Enum.find(@pages, &(&1["path"] == path <> "/unlock" and &1["status"] == 302))

    response = request(unlock, nil)
    {name, response |> cookie_lines() |> Map.fetch!(name) |> elem(0)}
  end

  defp cookie_lines(conn) do
    for {"set-cookie", line} <- conn.resp_headers, into: %{} do
      [pair | attributes] = line |> String.split(";") |> Enum.map(&String.trim/1)
      [name, value] = String.split(pair, "=", parts: 2)

      attributes =
        attributes
        |> Enum.map(&(&1 |> String.downcase() |> String.replace(~r/\Aexpires=.*/, "expires")))
        |> Enum.sort()

      {name, {value, attributes}}
    end
  end

  defp header(conn, name), do: conn |> get_resp_header(name) |> Enum.join(", ")

  defp head(html) do
    html
    |> ParityHTML.without([@scripts], "head")
    |> Enum.map(fn {"head", attrs, children} ->
      {"head", attrs, Enum.map(children, &undigest_meta/1)}
    end)
  end

  defp undigest_meta({"meta", attrs, children}),
    do:
      {"meta",
       Enum.map(attrs, fn
         {"content", value} -> {"content", String.replace(value, ~r/-[0-9a-f]{64}(?=\.)/, "")}
         other -> other
       end), children}

  defp undigest_meta(node), do: node

  defp data_attributes(html), do: ParityHTML.stimulus(html, "*")

  defp unmask(value) do
    <<pad::binary-size(32), masked::binary-size(32)>> = Base.url_decode64!(value, padding: false)
    pad |> :crypto.exor(masked) |> Base.encode16(case: :lower)
  end

  test "the unlock form and the csrf meta carry the tokens Rails derives from the session" do
    csrf = SharingSeeds.fixture("csrf.json")
    id = csrf["action"] |> String.split("/") |> Enum.at(2)
    cookie = Dawarich.Test.RailsUser.cookie(%{"_csrf_token" => csrf["session"]})
    html = conn({"_dawarich_session", cookie}) |> get("/s/#{id}") |> html_response(401)
    doc = LazyHTML.from_document(html)

    assert doc
           |> LazyHTML.query(~s(input[name="authenticity_token"]))
           |> LazyHTML.attribute("value")
           |> Enum.map(&unmask/1) ==
             [csrf["form"]]

    assert doc
           |> LazyHTML.query(~s(meta[name="csrf-token"]))
           |> LazyHTML.attribute("content")
           |> Enum.map(&unmask/1) ==
             [csrf["meta"]]
  end

  for page <- @pages do
    @page page

    test "#{page["name"]} answers as Rails does" do
      id = @page["path"] |> String.split("/") |> Enum.at(2) |> String.split("?") |> hd()
      cookie = unlocked(@page)
      before = @page["touched"] && SharingSeeds.view_count(id)
      conn = request(@page, cookie)

      assert conn.status == @page["status"]

      for {name, value} <- @page["headers"], do: assert(header(conn, name) == value, name)

      assert header(conn, "etag") != "" == @page["etag"]

      assert Map.new(cookie_lines(conn), fn {name, {_value, attrs}} -> {name, attrs} end) ==
               @page["set_cookies"]

      if @page["touched"], do: assert(SharingSeeds.view_count(id) - before == @page["touched"])

      if @page["title"] do
        html = conn.resp_body
        rails = SharingSeeds.page("#{@page["name"]}.html")
        rails_head = SharingSeeds.page("#{@page["name"]}.head.html")

        assert ParityHTML.fragment(html, "body > *") == ParityHTML.normalize(rails)

        body =
          html |> LazyHTML.from_document() |> LazyHTML.query("body > *") |> LazyHTML.to_html()

        assert data_attributes(body) == data_attributes(rails)

        assert head(html) == head("<html><head>#{rails_head}</head><body></body></html>")
        assert html =~ ~s(<html lang="#{@page["html_lang"]}">)
      end
    end
  end
end
