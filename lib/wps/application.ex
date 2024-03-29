defmodule WPS.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        WPSWeb.Telemetry,
        # WPS.Repo,
        {DNSCluster, query: Application.get_env(:wps, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: WPS.PubSub},
        {WPS.Tracker, name: WPS.Tracker, pubsub_server: WPS.PubSub},
        WPS.Members,
        # Start a worker by calling: WPS.Worker.start_link(arg)
        # {WPS.Worker, arg},
        # Start to serve requests, typically the last entry
        !System.get_env("SKIP_HEADLESS_DRIVER") && WPS.Browser.HeadlessDriver,
        {Task.Supervisor, name: WPS.TaskSup},
        WPSWeb.Endpoint
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
