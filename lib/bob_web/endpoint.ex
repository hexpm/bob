defmodule BobWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :bob
  use Sentry.PlugCapture

  @session_options [
    store: :cookie,
    key: "_bob_key",
    signing_salt: "9kLm2Qx7",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Bob.Plug.Forwarded)
  plug(Bob.Plug.Status)

  plug(Plug.Static,
    at: "/",
    from: :bob,
    gzip: Mix.env() != :dev,
    only: BobWeb.static_paths()
  )

  if Mix.env() == :dev do
    plug(Tidewave)
  end

  if code_reloading? do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(Logster.Plugs.Logger, excludes: [:params])
  plug(BobWeb.Plugs.Secret, api_only: true)

  plug(Plug.Parsers,
    parsers: [:json, Bob.Plug.Parser],
    pass: ["application/json", "application/vnd.bob+erlang"],
    json_decoder: JSON
  )

  plug(Sentry.PlugContext)
  plug(Plug.Session, @session_options)
  plug(BobWeb.Router)
end
