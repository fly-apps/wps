defmodule WPS.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    parent = FLAME.Parent.get()
    local_backend? = FLAME.Backend.impl() == FLAME.LocalBackend

    children =
      [
        WPSWeb.Telemetry,
        # WPS.Repo,
        !parent && {DNSCluster, query: Application.get_env(:wps, :dns_cluster_query) || :ignore},
        !parent && {Phoenix.PubSub, name: WPS.PubSub},
        !parent && {WPS.Tracker, name: WPS.Tracker, pubsub_server: WPS.PubSub},
        !parent && WPS.Members,
        !parent && WPS.RateLimiter,
        # Start a worker by calling: WPS.Worker.start_link(arg)
        # {WPS.Worker, arg},
        # Start to serve requests, typically the last entry
        if(parent || local_backend?, do: WPS.Browser.HeadlessDriver),
        !parent &&
          {FLAME.Pool,
           name: WPS.BrowserRunner,
           min: 0,
           max: 5,
           max_concurrency: 20,
           min_idle_shutdown_after: :timer.seconds(30),
           idle_shutdown_after: :timer.seconds(30),
           log: :info},
        {Task.Supervisor, name: WPS.TaskSup},
        !parent && WPSWeb.Endpoint
      ]
      |> Enum.filter(& &1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WPS.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WPSWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
