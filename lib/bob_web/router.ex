defmodule BobWeb.Router do
  use BobWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {BobWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/api", BobWeb do
    post("/queue/start", QueueController, :start)
    post("/queue/success", QueueController, :success)
    post("/queue/failure", QueueController, :failure)
    post("/queue/add", QueueController, :add)
    post("/artifacts/add", ArtifactController, :add)
    post("/docker/add", ArtifactController, :add_docker)
  end

  scope "/", BobWeb do
    pipe_through(:browser)

    live("/", JobsLive)
    live("/artifacts", ArtifactsLive)
    live("/docker", DockerTagsLive)
  end
end
