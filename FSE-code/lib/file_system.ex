defmodule FileSystem do
  @moduledoc """
  Modern file system change watcher for Elixir.

  This module provides a high-level API for monitoring file system changes across
  multiple platforms (macOS, Linux, Windows). It supports advanced features including
  filtering, throttling, deduplication, debouncing, batching, and async processing.

  ## Architecture

  The FileSystem module uses a GenServer-based architecture where:
  - A Worker process manages the backend and subscribers
  - Platform-specific backends handle native file system monitoring
  - Events flow through filtering, throttling, and processing pipelines
  - Subscribers receive events via message passing
  """

  @doc """
  Starts a modern `GenServer` process to watch file system changes.

  ## Options

    * `:dirs` ([string], required), the list of directories to monitor.

    * `:backend` (atom, optional), default backends: `:fs_mac`. Available
      backends: `:fs_mac`, `:fs_inotify`, `:fs_windows`, and `:fs_poll`.

    * `:name` (atom, optional), the `name` of the worker process to subscribe
      to the file system listener. Alternative to using `pid` of the worker
      process.

    * `:extensions` (list, optional), filter events by file extensions (e.g., [".ex", ".exs"]).

    * `:patterns` (list, optional), filter events by glob patterns (e.g., ["**/*.ex"]).

    * `:exclude_patterns` (list, optional), exclude events matching these patterns.

    * `:regex` (string or Regex, optional), filter events by regular expression.

    * `:exclude_regex` (string or Regex, optional), exclude events matching this regex.

    * `:filter_fn` (function, optional), custom filter function `(path -> boolean)`.

    * `:throttle` (boolean, optional), enable/disable throttling (default: true).

    * `:max_events` (integer, optional), max events per window for throttling (default: 100).

    * `:window_ms` (integer, optional), throttling window in milliseconds (default: 1000).

    * `:debounce_ms` (integer, optional), debounce delay in milliseconds (default: 0).

    * `:deduplicate` (boolean, optional), enable event deduplication (default: true).

    * `:batch_size` (integer, optional), batch events together (default: 1).

    * `:batch_timeout_ms` (integer, optional), timeout for batching in milliseconds (default: 0).

    * `:async` (boolean, optional), process events asynchronously (default: false).

    * Additional backend implementation options. See backend module documents
      for more details.

  ## Examples

  Start monitoring `/tmp/fs` directory using the default `:fs_mac` backend:

      iex> {:ok, pid} = FileSystem.start_link(dirs: ["/tmp/fs"])
      iex> FileSystem.subscribe(pid)

  Monitor only Elixir files:

      iex> FileSystem.start_link(
      ...>   dirs: ["/path/to/project"],
      ...>   extensions: [".ex", ".exs"]
      ...> )

  Monitor with custom filtering and throttling:

      iex> FileSystem.start_link(
      ...>   dirs: ["/path/to/files"],
      ...>   patterns: ["lib/**/*.ex"],
      ...>   exclude_patterns: ["**/test/**"],
      ...>   max_events: 50,
      ...>   window_ms: 500
      ...> )

  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(options) do
    FileSystem.Worker.start_link(options)
  end

  @doc """
  Register the current process as a subscriber of a `file_system` worker.

  The `pid` you subscribed from will now receive messages like:

      {:file_event, worker_pid, {file_path, events}}
      {:file_event, worker_pid, :stop}

  """
  @spec subscribe(GenServer.server()) :: :ok
  def subscribe(pid) do
    GenServer.call(pid, :subscribe)
  end

  @doc """
  Get statistics about the file system worker.

  Returns a map with:
  - `:events_received` - Total events received from backend
  - `:events_filtered` - Events filtered out
  - `:events_throttled` - Events rate limited
  - `:events_sent` - Events sent to subscribers
  """
  @spec stats(GenServer.server()) :: map()
  def stats(pid) do
    GenServer.call(pid, :stats)
  end

  @doc """
  Check the health status of the file system worker.

  Returns `:healthy`, `:degraded`, or `:unhealthy`.
  """
  @spec health(GenServer.server()) :: :healthy | :degraded | :unhealthy
  def health(pid) do
    GenServer.call(pid, :health)
  end

  @doc """
  Get the current configuration of the file system worker.
  """
  @spec config(GenServer.server()) :: map()
  def config(pid) do
    GenServer.call(pid, :config)
  end
end
