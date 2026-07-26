defmodule Bob.PromEx do
  use PromEx, otp_app: :bob

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, router: BobWeb.Router, endpoint: BobWeb.Endpoint},
      Bob.PromEx.Plugins.Bob
    ] ++ master_plugins()
  end

  # Agents run without Bob.Repo, so the Ecto plugin would crash them
  defp master_plugins() do
    if Application.get_env(:bob, :master?) do
      [{Plugins.Ecto, repos: [Bob.Repo]}]
    else
      []
    end
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"}
    ]
  end
end
