require Logger

defmodule FileSystem.Worker do
  @moduledoc """
  Core worker process for file system monitoring.

  This GenServer manages the lifecycle of file system monitoring, including:
  - Backend process management and supervision
  - Event processing pipeline (filtering, throttling, deduplication)
  - Subscriber management
  - Statistics and health monitoring
  - Telemetry event emission

  ## Event Processing Pipeline

  1. Events are received from the backend
  2. Filtered based on configured rules (extensions, patterns, regex, etc.)
  3. Checked for duplicates (if deduplication enabled)
  4. Throttled if rate limits are exceeded
  5. Debounced or batched if configured
  6. Sent to all subscribers (synchronously or asynchronously)

  Created by mehdi.
  """

  use GenServer

  @doc false
  def start_link(args) do
    with {:ok, config} <- FileSystem.Config.validate(args),
         {name_opts, rest_opts} <- Keyword.split(args, [:name]) do
      GenServer.start_link(__MODULE__, config, name_opts)
    else
      {:error, reason} ->
        Logger.error("Invalid FileSystem configuration: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc false
  def init(config) do
    Process.flag(:trap_exit, true)

    with {:ok, backend_module} <- FileSystem.Backend.backend(config.backend),
         {:ok, backend_pid} <-
           backend_module.start_link([
             {:worker_pid, self()}
             | Map.take(config, [:dirs])
             |> Map.to_list()
           ]) do
      state = build_initial_state(config, backend_pid, backend_module)

      emit_telemetry(:worker_started, %{backend: backend_module})

      {:ok, state}
    else
      {:error, reason} = error ->
        Logger.error("Failed to start file_system worker: #{inspect(reason)}")
        emit_telemetry(:worker_start_failed, %{reason: reason})
        error
    end
  end

  defp build_initial_state(config, backend_pid, backend_module) do
    throttle_pid = maybe_start_throttle(config)
    deduplicator_pid = maybe_start_deduplicator(config)
    debouncer_pid = maybe_start_debouncer(config)
    batcher_pid = maybe_start_batcher(config)

    %{
      backend_pid: backend_pid,
      backend_module: backend_module,
      subscribers: %{},
      config: config,
      filter_opts: config.filter_opts,
      throttle_pid: throttle_pid,
      deduplicator_pid: deduplicator_pid,
      debouncer_pid: debouncer_pid,
      batcher_pid: batcher_pid,
      stats: %{
        events_received: 0,
        events_filtered: 0,
        events_throttled: 0,
        events_duplicate: 0,
        events_sent: 0,
        batches_sent: 0
      },
      started_at: System.monotonic_time(:second)
    }
  end

  defp maybe_start_throttle(%{throttle: true} = config) do
    opts = Map.take(config, [:max_events, :window_ms]) |> Map.to_list()

    case FileSystem.Throttle.start_link(opts) do
      {:ok, pid} -> pid
      _ -> nil
    end
  end

  defp maybe_start_throttle(_), do: nil

  defp maybe_start_deduplicator(%{deduplicate: true}) do
    case FileSystem.Deduplicator.start_link([]) do
      {:ok, pid} -> pid
      _ -> nil
    end
  end

  defp maybe_start_deduplicator(_), do: nil

  defp maybe_start_debouncer(%{debounce_ms: ms}) when ms > 0 do
    case FileSystem.Debouncer.start_link(debounce_ms: ms) do
      {:ok, pid} -> pid
      _ -> nil
    end
  end

  defp maybe_start_debouncer(_), do: nil

  defp maybe_start_batcher(%{batch_size: size, batch_timeout_ms: timeout} = config)
       when size > 1 or timeout > 0 do
    opts = Map.take(config, [:batch_size, :batch_timeout_ms]) |> Map.to_list()

    case FileSystem.Batcher.start_link(opts) do
      {:ok, pid} -> pid
      _ -> nil
    end
  end

  defp maybe_start_batcher(_), do: nil

  @doc false
  def handle_call(:subscribe, {pid, _}, state) do
    ref = Process.monitor(pid)
    state = put_in(state, [:subscribers, ref], pid)
    emit_telemetry(:subscriber_added, %{subscriber_count: map_size(state.subscribers) + 1})
    {:reply, :ok, state}
  end

  @doc false
  def handle_call(:stats, _from, state) do
    uptime = System.monotonic_time(:second) - state.started_at
    enhanced_stats = Map.put(state.stats, :uptime_seconds, uptime)
    {:reply, enhanced_stats, state}
  end

  @doc false
  def handle_call(:health, _from, state) do
    health =
      cond do
        not Process.alive?(state.backend_pid) -> :unhealthy
        map_size(state.subscribers) == 0 -> :degraded
        true -> :healthy
      end

    {:reply, health, state}
  end

  @doc false
  def handle_call(:config, _from, state) do
    {:reply, state.config, state}
  end

  @doc false
  def handle_info(
        {:backend_file_event, backend_pid, file_event},
        %{backend_pid: backend_pid} = state
      ) do
    state = update_in(state.stats.events_received, &(&1 + 1))
    emit_telemetry(:event_received, %{})

    case file_event do
      :stop ->
        broadcast_event(state, file_event)
        {:stop, :normal, state}

      {path, events} ->
        process_event(path, events, state)
    end
  end

  def handle_info({:EXIT, pid, reason}, state) when pid == state.backend_pid do
    Logger.warning("Backend process exited: #{inspect(reason)}")
    emit_telemetry(:backend_exited, %{reason: reason})
    {:stop, {:backend_exited, reason}, state}
  end

  defp process_event(path, events, state) do
    cond do
      not should_process_event?(path, state) ->
        state = update_in(state.stats.events_filtered, &(&1 + 1))
        emit_telemetry(:event_filtered, %{path: path})
        {:noreply, state}

      check_throttle(state) == :throttled ->
        state = update_in(state.stats.events_throttled, &(&1 + 1))
        emit_telemetry(:event_throttled, %{path: path})
        {:noreply, state}

      check_duplicate(path, events, state) == :duplicate ->
        state = update_in(state.stats.events_duplicate, &(&1 + 1))
        emit_telemetry(:event_duplicate, %{path: path})
        {:noreply, state}

      true ->
        send_event(path, events, state)
    end
  end

  defp send_event(path, events, state) do
    callback = fn event_data ->
      if state.config.async do
        Task.start(fn -> broadcast_event(state, event_data) end)
      else
        broadcast_event(state, event_data)
      end
    end

    batch_callback = fn batch_events ->
      if state.config.async do
        Task.start(fn ->
          broadcast_batch(state, batch_events)
          emit_telemetry(:batch_sent, %{batch_size: length(batch_events)})
        end)
      else
        broadcast_batch(state, batch_events)
        emit_telemetry(:batch_sent, %{batch_size: length(batch_events)})
      end
    end

    state =
      cond do
        state.debouncer_pid && state.config.debounce_ms > 0 ->
          FileSystem.Debouncer.schedule(state.debouncer_pid, path, events, callback)
          state

        state.batcher_pid && (state.config.batch_size > 1 || state.config.batch_timeout_ms > 0) ->
          FileSystem.Batcher.add(state.batcher_pid, path, events, batch_callback)
          state = update_in(state.stats.batches_sent, &(&1 + 1))
          state

        true ->
          callback.({path, events})
          state = update_in(state.stats.events_sent, &(&1 + 1))
          emit_telemetry(:event_sent, %{path: path, events: events})
          state
      end

    {:noreply, state}
  end

  defp check_duplicate(_path, _events, %{deduplicator_pid: nil}), do: :ok

  defp check_duplicate(path, events, %{deduplicator_pid: pid}) do
    try do
      FileSystem.Deduplicator.check(pid, path, events)
    rescue
      _ -> :ok
    end
  end

  def handle_info({:DOWN, ref, _, _pid, _reason}, state) do
    subscribers = Map.drop(state.subscribers, [ref])
    emit_telemetry(:subscriber_removed, %{subscriber_count: map_size(subscribers)})
    {:noreply, %{state | subscribers: subscribers}}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  defp should_process_event?(path, state) do
    if Enum.empty?(state.filter_opts) do
      true
    else
      FileSystem.Filter.matches?(path, state.filter_opts)
    end
  end

  defp check_throttle(%{throttle_pid: nil}), do: :ok

  defp check_throttle(%{throttle_pid: pid}) do
    try do
      FileSystem.Throttle.check(pid)
    rescue
      _ -> :ok
    end
  end

  defp broadcast_event(state, file_event) when is_tuple(file_event) do
    {path, events} = file_event
    Enum.each(state.subscribers, fn {_ref, subscriber_pid} ->
      send(subscriber_pid, {:file_event, self(), {path, events}})
    end)
  end

  defp broadcast_event(state, file_event) do
    Enum.each(state.subscribers, fn {_ref, subscriber_pid} ->
      send(subscriber_pid, {:file_event, self(), file_event})
    end)
  end

  defp broadcast_batch(state, events) when is_list(events) do
    Enum.each(state.subscribers, fn {_ref, subscriber_pid} ->
      send(subscriber_pid, {:file_event_batch, self(), events})
    end)
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute([:file_system, event], %{count: 1}, metadata)
  rescue
    _ -> :ok
  end
end
