defmodule FileSystem.Batcher do
  @moduledoc """
  Event batching to group multiple events together for efficient processing.

  This module collects multiple file system events and groups them into batches
  before processing. This reduces overhead when many files change simultaneously,
  such as during large directory operations or build processes.

  ## How It Works

  Events are collected in a buffer until either:
  - The batch size limit is reached, or
  - A timeout expires

  When either condition is met, all buffered events are sent together as a single
  batch to the callback function.

  ## Configuration

  - `batch_size`: Maximum number of events per batch (default: 1, disabled)
  - `batch_timeout_ms`: Maximum time to wait before flushing (default: 0, disabled)

  Created by mehdi.
  """

  use GenServer

  @doc """
  Starts a batcher process.
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Adds an event to the batch.

  The callback will receive a list of batched events: `[{path, events}, ...]`
  """
  @spec add(GenServer.server(), String.t(), [atom()], function()) :: :ok
  def add(pid, path, events, callback) do
    GenServer.cast(pid, {:add, path, events, callback})
  end

  def init(opts) do
    batch_size = Keyword.get(opts, :batch_size, 1)
    timeout_ms = Keyword.get(opts, :batch_timeout_ms, 0)

    {:ok,
     %{
       batch_size: batch_size,
       timeout_ms: timeout_ms,
       batch: [],
       timer: nil
     }}
  end

  def handle_cast({:add, path, events, callback}, state) do
    new_batch = [{path, events, callback} | state.batch]
    state = %{state | batch: new_batch}

    state =
      if length(new_batch) >= state.batch_size do
        flush_batch(state)
      else
        maybe_schedule_timeout(state)
      end

    {:noreply, state}
  end

  def handle_info(:batch_timeout, state) do
    {:noreply, flush_batch(%{state | timer: nil})}
  end

  defp flush_batch(%{batch: []} = state), do: state

  defp flush_batch(state) do
    events = Enum.reverse(state.batch)

    event_data =
      Enum.map(events, fn {path, event_list, _callback} ->
        {path, event_list}
      end)

    # Use the last callback (they should all be the same)
    callback = List.last(events) |> elem(2)
    callback.(event_data)

    %{state | batch: [], timer: nil}
  end

  defp maybe_schedule_timeout(%{timeout_ms: 0} = state), do: state

  defp maybe_schedule_timeout(%{timer: nil, timeout_ms: timeout_ms} = state) do
    timer = Process.send_after(self(), :batch_timeout, timeout_ms)
    %{state | timer: timer}
  end

  defp maybe_schedule_timeout(state), do: state
end
