defmodule FileSystem.Debouncer do
  @moduledoc """
  Event debouncing to delay event processing until activity stops.

  This module implements debouncing, which delays the processing of events until
  there's been a period of inactivity. This is useful for scenarios where rapid
  successive changes to the same file should be treated as a single event.

  ## How It Works

  When an event is scheduled, a timer is set. If another event for the same path
  arrives before the timer expires, the previous timer is cancelled and a new one
  is started. Only when the timer expires without new events does the callback
  execute.

  ## Use Cases

  - File editing: Multiple rapid saves should trigger one reload
  - Build systems: Multiple file changes should trigger one rebuild
  - UI updates: Rapid changes should result in one update

  Created by mehdi.
  """

  use GenServer

  @doc """
  Starts a debouncer process.
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Schedules an event to be processed after debounce delay.
  Returns the scheduled event ID.
  """
  @spec schedule(GenServer.server(), String.t(), [atom()], function()) :: reference()
  def schedule(pid, path, events, callback) do
    GenServer.cast(pid, {:schedule, path, events, callback})
  end

  def init(opts) do
    delay_ms = Keyword.get(opts, :debounce_ms, 0)
    {:ok, %{delay_ms: delay_ms, timers: %{}}}
  end

  def handle_cast({:schedule, path, events, callback}, state) do
    key = {path, events}

    state =
      case Map.get(state.timers, key) do
        nil ->
          timer = schedule_timer(key, callback, state.delay_ms)
          put_in(state.timers[key], timer)

        existing_timer ->
          Process.cancel_timer(existing_timer)
          timer = schedule_timer(key, callback, state.delay_ms)
          put_in(state.timers[key], timer)
      end

    {:noreply, state}
  end

  def handle_info({:debounce_trigger, key, callback}, state) do
    callback.()
    {:noreply, %{state | timers: Map.delete(state.timers, key)}}
  end

  defp schedule_timer(key, callback, delay_ms) do
    Process.send_after(self(), {:debounce_trigger, key, callback}, delay_ms)
  end
end
