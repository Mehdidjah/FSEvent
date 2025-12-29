defmodule FileSystem.Throttle do
  @moduledoc """
  Rate limiting and throttling for file system events.

  This module implements a sliding window rate limiter to prevent overwhelming
  subscribers with too many events in a short time period. It uses a time-based
  window to track events and automatically cleans up old entries.

  ## How It Works

  The throttle maintains a list of event timestamps within a configurable time window.
  When the number of events exceeds the maximum allowed, new events are throttled
  (rejected) until the window slides forward and old events expire.

  ## Configuration

  - `max_events`: Maximum number of events allowed per window (default: 100)
  - `window_ms`: Time window in milliseconds (default: 1000)

  Created by mehdi.
  """

  use GenServer

  @doc """
  Starts a throttle process.

  ## Options
  - `:max_events` - Maximum number of events per window (default: 100)
  - `:window_ms` - Time window in milliseconds (default: 1000)
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Checks if an event should be allowed through the throttle.
  Returns `:ok` if allowed, `:throttled` if rate limited.
  """
  @spec check(GenServer.server()) :: :ok | :throttled
  def check(pid \\ __MODULE__) do
    GenServer.call(pid, {:check, nil}, :infinity)
  end

  def init(opts) do
    max_events = Keyword.get(opts, :max_events, 100)
    window_ms = Keyword.get(opts, :window_ms, 1000)

    {:ok,
     %{
       max_events: max_events,
       window_ms: window_ms,
       events: [],
       last_cleanup: System.monotonic_time(:millisecond)
     }}
  end

  def handle_call({:check, _path}, _from, state) do
    now = System.monotonic_time(:millisecond)
    state = cleanup_old_events(state, now)

    if length(state.events) >= state.max_events do
      {:reply, :throttled, state}
    else
      new_events = [now | state.events]
      {:reply, :ok, %{state | events: new_events}}
    end
  end

  defp cleanup_old_events(state, now) do
    cutoff = now - state.window_ms
    filtered_events = Enum.filter(state.events, &(&1 > cutoff))

    %{state | events: filtered_events, last_cleanup: now}
  end
end
