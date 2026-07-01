defmodule BobWeb.Router do
  use BobWeb, :router

  import BobWeb.UserAuth

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {BobWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:fetch_current_user)
  end

  pipeline :public_api do
    plug(:accepts, ["json"])
  end

  # Authenticated in the endpoint by BobWeb.Plugs.Secret, before body parsing.
  scope "/api", BobWeb do
    post("/queue/start", QueueController, :start)
    post("/queue/success", QueueController, :success)
    post("/queue/failure", QueueController, :failure)
    post("/queue/requeue", QueueController, :requeue)
    post("/queue/add", QueueController, :add)
    post("/artifacts/add", ArtifactController, :add)
    post("/docker/add", ArtifactController, :add_docker)
  end

  # Public API routes, exempted from agent auth in BobWeb.Plugs.Secret.
  scope "/api", BobWeb do
    pipe_through(:public_api)

    get("/artifacts", PublicApiController, :artifacts)
    get("/docker", PublicApiController, :docker_tags)
  end

  scope "/", BobWeb do
    pipe_through(:browser)

    get("/oauth/login", OAuthController, :login)
    get("/oauth/callback", OAuthController, :callback)
    post("/oauth/logout", OAuthController, :logout)

    live_session :default, on_mount: [{BobWeb.UserAuth, :mount_current_user}] do
      live("/", JobsLive)
      live("/artifacts", ArtifactsLive)
      live("/docker", DockerTagsLive)
    end
  end

  scope "/", BobWeb do
    pipe_through([:browser, :require_authenticated_user])

    live_session :authenticated, on_mount: [{BobWeb.UserAuth, :ensure_authenticated}] do
      live("/request", RequestLive)
    end
  end
end
