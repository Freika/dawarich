# frozen_string_literal: true

module PhoenixAdmissionProbe
  def admission_probe
    <<~SH
      if [ "$1" = eval ] && [ "$2" = 'if !Dawarich.Release.Lifecycle.admitted?(), do: System.halt(1)' ]; then
        exec env ASDF_ERLANG_VERSION=27.3.4.1 ASDF_ELIXIR_VERSION=1.18.3-otp-27 \\
          PHOENIX_TEST_REDIS_URL="#{ENV.fetch('REDIS_URL')}" \\
          "#{File.expand_path('~/.asdf/shims/elixir')}" --erl '+S 1:1' \\
          -pa "#{root}/app-phoenix/_build/test/lib/dawarich/ebin" -e "$2"
      fi
    SH
  end
end
