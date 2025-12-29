defmodule FileSystem.Config do
  @moduledoc """
  Configuration validation and normalization for FileSystem.

  This module provides comprehensive validation of FileSystem configuration options,
  ensuring type safety and value constraints. It also normalizes configuration with
  sensible defaults.

  ## Validation

  The module validates:
  - Required options (e.g., `:dirs` must be present and non-empty)
  - Type correctness (integers, booleans, lists, etc.)
  - Value constraints (positive numbers, valid ranges, etc.)

  ## Defaults

  Sensible defaults are provided for all optional configuration options, allowing
  users to configure only what they need while maintaining good default behavior.

  Created by mehdi.
  """

  @defaults %{
    throttle: true,
    max_events: 100,
    window_ms: 1000,
    debounce_ms: 0,
    deduplicate: true,
    batch_size: 1,
    batch_timeout_ms: 0,
    async: false
  }

  @doc """
  Validates and normalizes configuration options.
  """
  @spec validate(Keyword.t()) :: {:ok, map()} | {:error, String.t()}
  def validate(opts) do
    with :ok <- validate_required(opts),
         :ok <- validate_types(opts),
         :ok <- validate_values(opts) do
      normalized = normalize(opts)
      {:ok, normalized}
    end
  end

  defp validate_required(opts) do
    if Keyword.has_key?(opts, :dirs) and is_list(Keyword.get(opts, :dirs)) and
         length(Keyword.get(opts, :dirs)) > 0 do
      :ok
    else
      {:error, ":dirs option is required and must be a non-empty list"}
    end
  end

  defp validate_types(opts) do
    validations = [
      {:max_events, &is_integer/1, "must be an integer"},
      {:window_ms, &is_integer/1, "must be an integer"},
      {:debounce_ms, &is_integer/1, "must be an integer"},
      {:batch_size, &is_integer/1, "must be an integer"},
      {:batch_timeout_ms, &is_integer/1, "must be an integer"},
      {:throttle, &is_boolean/1, "must be a boolean"},
      {:deduplicate, &is_boolean/1, "must be a boolean"},
      {:async, &is_boolean/1, "must be a boolean"}
    ]

    Enum.reduce_while(validations, :ok, fn {key, validator, error_msg}, _acc ->
      case Keyword.get(opts, key) do
        nil -> {:cont, :ok}
        value when validator.(value) -> {:cont, :ok}
        _ -> {:halt, {:error, "#{key} #{error_msg}"}}
      end
    end)
  end

  defp validate_values(opts) do
    validations = [
      {:max_events, &(&1 > 0), "must be greater than 0"},
      {:window_ms, &(&1 > 0), "must be greater than 0"},
      {:debounce_ms, &(&1 >= 0), "must be greater than or equal to 0"},
      {:batch_size, &(&1 > 0), "must be greater than 0"},
      {:batch_timeout_ms, &(&1 >= 0), "must be greater than or equal to 0"}
    ]

    Enum.reduce_while(validations, :ok, fn {key, validator, error_msg}, _acc ->
      case Keyword.get(opts, key) do
        nil -> {:cont, :ok}
        value when validator.(value) -> {:cont, :ok}
        _ -> {:halt, {:error, "#{key} #{error_msg}"}}
      end
    end)
  end

  defp normalize(opts) do
    @defaults
    |> Map.merge(Enum.into(opts, %{}))
    |> Map.put(:dirs, Keyword.get(opts, :dirs))
    |> Map.put(:backend, Keyword.get(opts, :backend))
    |> Map.put(:name, Keyword.get(opts, :name))
    |> Map.put(:filter_opts, extract_filter_opts(opts))
  end

  defp extract_filter_opts(opts) do
    Keyword.take(opts, [
      :extensions,
      :patterns,
      :exclude_patterns,
      :regex,
      :exclude_regex,
      :filter_fn
    ])
  end
end
