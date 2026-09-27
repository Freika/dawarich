defmodule DawarichWeb.Head do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]

  attr :locale, :string, required: true

  def pwa_meta(assigns),
    do: ~H"""
    <meta name="mobile-web-app-capable" content="yes" /><meta
      name="apple-mobile-web-app-capable"
      content="yes"
    /><meta name="apple-mobile-web-app-status-bar-style" content="default" /><meta
      name="apple-mobile-web-app-title"
      content={t(@locale, "common.app_name", %{})}
    />
    """

  def favicon(assigns),
    do: ~H"""
    <link
      rel="apple-touch-icon"
      sizes="180x180"
      href={DawarichWeb.Assets.stylesheet_path("favicon/apple-touch-icon.png")}
    />
    <link
      rel="icon"
      type="image/png"
      sizes="32x32"
      href={DawarichWeb.Assets.stylesheet_path("favicon/favicon-32x32.png")}
    />
    <link
      rel="icon"
      type="image/png"
      sizes="16x16"
      href={DawarichWeb.Assets.stylesheet_path("favicon/favicon-16x16.png")}
    />
    <link rel="manifest" href="/site.webmanifest" />
    <link
      rel="mask-icon"
      href={DawarichWeb.Assets.stylesheet_path("favicon/safari-pinned-tab.svg")}
      color="#1775fc"
    />
    <link rel="shortcut icon" href={DawarichWeb.Assets.stylesheet_path("favicon/favicon.ico")} />
    <meta name="msapplication-TileColor" content="#1775fc" />
    <meta
      name="msapplication-config"
      content={DawarichWeb.Assets.stylesheet_path("favicon/browserconfig.xml")}
    />
    <meta name="theme-color" content="#ffffff" />
    """

  attr :self_hosted, :boolean, required: true

  def head_scripts(assigns) do
    assigns =
      assign(assigns,
        paddle_environment: System.get_env("PADDLE_BILLING_ENVIRONMENT", "production"),
        paddle_token: System.get_env("PADDLE_BILLING_CLIENT_TOKEN", ""),
        partnero_program_id: System.get_env("PARTNERO_PROGRAM_ID"),
        google_ads_id: System.get_env("GOOGLE_ADS_ID"),
        manager_host: System.get_env("MANAGER_HOST")
      )

    ~H"""
    <%= if System.get_env("POSTHOG_ENABLED") == "true" do %>
      <script src={DawarichWeb.Assets.stylesheet_path("posthog.js")} data-turbo-track="reload">
      </script>
    <% end %>
    <%= unless @self_hosted do %>
      <script async src="https://scripts.simpleanalyticscdn.com/latest.js">
      </script>
      <script src="https://rybbit.dwri.xyz/api/script.js" data-site-id="87c1f532b59f" defer>
      </script>
      <.paddle_script environment={@paddle_environment} token={@paddle_token} />
      <%= if @partnero_program_id do %>
        <script>
          (function(p,t,n,e,r,o){ p['__partnerObject']=r;function f(){var c={ a:arguments,q:[]};var r=this.push(c);return "number"!=typeof r?r:f.bind(c.q);}f.q=f.q||[];p[r]=p[r]||f.bind(f.q);p[r].q=p[r].q||f.q;o=t.createElement(n);var _=t.getElementsByTagName(n)[0];o.async=1;o.src=e+'?v'+(~~(new Date().getTime()/1e6));_.parentNode.insertBefore(o,_);})(window,document,'script','https://app.partnero.com/js/universal.js','po');
          po('settings','assets_host','https://assets.partnero.com');
          po('program',{Phoenix.HTML.raw(Jason.encode!(@partnero_program_id))},'load');
        </script>
      <% end %>
      <%= if @google_ads_id do %>
        <script async src={"https://www.googletagmanager.com/gtag/js?id=#{@google_ads_id}"}>
        </script>
        <script>
          window.dataLayer = window.dataLayer || [];
          function gtag(){dataLayer.push(arguments);}
          gtag('js', new Date());
          gtag('config', {Phoenix.HTML.raw(Jason.encode!(@google_ads_id))}, { send_page_view: false, linker: { accept_incoming: true, domains: {Phoenix.HTML.raw(Jason.encode!(Enum.reject([@manager_host], &is_nil/1)))} } });
        </script>
      <% end %>
    <% end %>
    """
  end

  defp paddle_script(assigns) do
    assigns =
      assign(assigns,
        environment: Jason.encode!(assigns.environment),
        token: Jason.encode!(assigns.token)
      )

    ~H"""
    <script
      async
      src="https://cdn.paddle.com/paddle/v2/paddle.js"
      onload={"\n        Paddle.Environment.set(#{@environment});\n        Paddle.Initialize({ token: #{@token} });\n      "}
    >
    </script>
    """
  end
end
