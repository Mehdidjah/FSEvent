defmodule FileSystem.Deduplicator do
  @moduledoc """
  Event deduplication to prevent processing duplicate events.

  This module tracks recently seen events and prevents duplicate events for the same
  file path and event types from being processed multiple times. It automatically
  cleans up old entries to prevent memory growth.

  ## How It Works

  The deduplicator maintains a map of recently seen events, keyed by file path
  and event types. When an event is checked, if it was recently seen, it's marked
  as a duplicate. Old entries are periodically cleaned up based on a configurable
  cleanup interval.

  Created by mehdi.
  """

  use GenServer

  @doc """
  Starts a deduplicator process.
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [])
  end

  @doc """
  Checks if an event should be processed (not a duplicate).
  Returns `:ok` if new, `:duplicate` if already seen.
  """
  @spec check(GenServer.server(), String.t(), [atom()]) :: :ok | :duplicate
  def check(pid, path, events) do
    GenServer.call(pid, {:check, path, events}, :infinity)
  end

  def init(_opts) do
    {:ok, %{seen: %{}, cleanup_interval: 5000}}
  end

  def handle_call({:check, path, events}, _from, state) do
    key = {path, Enum.sort(events)}
    now = System.monotonic_time(:millisecond)

    case Map.get(state.seen, key) do
      nil ->
        new_seen = Map.put(state.seen, key, now)
        schedule_cleanup(state.cleanup_interval)
        {:reply, :ok, %{state | seen: new_seen}}

      _timestamp ->
        {:reply, :duplicate, state}
    end
  end

  def handle_info(:cleanup, state) do
    cutoff = System.monotonic_time(:millisecond) - 10000
    cleaned = Map.filter(state.seen, fn {_key, timestamp} -> timestamp > cutoff end)
    {:noreply, %{state | seen: cleaned}}
  end

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
  end
end
