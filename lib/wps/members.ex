defmodule WPS.Members do
  use GenServer

  @tracker WPS.Tracker

  def list(group_name \\ __MODULE__) do
    Phoenix.Tracker.list(@tracker, group_name)
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    group_name = Keyword.get(opts, :name, __MODULE__)

    {:ok, ref} =
      Phoenix.Tracker.track(@tracker, self(), group_name, WPS.region(), %{
        node: Node.self(),
        machine_id: System.get_env("FLY_MACHINE_ID")
      })

    {:ok, %{group_name: group_name, ref: ref}}
  end
end
