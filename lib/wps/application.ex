defmodule WPS.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      children(
        always: WPSWeb.Telemetry,
        always: WPS.Repo,
        parent: {DNSCluster, query: Application.get_env(:wps, :dns_cluster_query) || :ignore},
        parent: {Phoenix.PubSub, name: WPS.PubSub},
        parent: {WPS.Tracker, name: WPS.Tracker, pubsub_server: WPS.PubSub},
        parent: WPS.Members,
        parent: WPS.RateLimiter,
        parent: WPS.Browser.HeadlessDriver,
        always:
          {FLAME.Pool,
           name: WPS.BrowserRunner,
           min: 0,
           max: 5,
           max_concurrency: 20,
           min_idle_shutdown_after: :timer.seconds(30),
           idle_shutdown_after: :timer.seconds(30),
           log: :info},
        parent: WPSWeb.Endpoint
      )

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WPS.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp children(child_specs) do
    is_parent? = !!(FLAME.Parent.get() || FLAME.Backend.impl() == FLAME.LocalBackend)

    Enum.flat_map(child_specs, fn
      {:always, spec} -> [spec]
      {:parent, spec} when is_parent? == true -> [spec]
      {:parent, _spec} when is_parent? == false -> []
      {:flame, _spec} when is_parent? == true -> []
      {:flame, spec} when is_parent? == false -> [spec]
    end)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WPSWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
