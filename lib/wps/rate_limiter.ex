defmodule WPS.RateLimiter do
  @moduledoc """
  Simple in-memory rate limiter using ETS.

  *Note*: Every restart or deploy will clear the rate limit history.
  Use accordingly.
  """
  use GenServer
  alias WPS.RateLimiter

  @table_name __MODULE__
  @reset_interval :timer.seconds(60)

  defstruct reset_interval: nil, tab: nil, timer_ref: nil

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def inc(tab \\ @table_name, key, limit_per_minute) do
    with true <- get_count(tab, key) <= limit_per_minute,
         new_count = :ets.update_counter(tab, key, 1, {key, 0}),
         true <- new_count <= limit_per_minute do
      {:ok, new_count}
    else
      _ -> {:error, :rate_limited}
    end
  end

  def get_count(tab \\ @table_name, key) do
    case :ets.lookup(tab, key) do
      [{^key, count}] -> count
      [] -> 0
    end
  end

  @impl true
  def init(_opts) do
    tab =
      :ets.new(@table_name, [
        :named_table,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])

    state = %RateLimiter{reset_interval: @reset_interval, tab: tab}
    {:ok, schedule_reset(state)}
  end

  @impl true
  def handle_info(:reset, %RateLimiter{} = state) do
    :ets.delete_all_objects(state.tab)
    {:noreply, schedule_reset(state)}
  end

  defp schedule_reset(%RateLimiter{} = state) do
    timer_ref = Process.send_after(self(), :reset, state.reset_interval)
    %RateLimiter{state | timer_ref: timer_ref}
  end
end
