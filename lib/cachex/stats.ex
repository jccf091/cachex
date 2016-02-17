defmodule Cachex.Stats do
  @moduledoc false
  # A simple statistics container, used to keep track of various operations on
  # a given cache. This container has no knowledge of the cache it belongs to,
  # it only keeps track of an internal struct. Provides shorthands for adding
  # various operations, as well as a helper for merging two stat containers as
  # needed (stats are a per-process state, so concurrency means aggregation).

  defstruct opCount: 0,         # number of operations on the cache
            setCount: 0,        # number of keys set on the cache
            hitCount: 0,        # number of times a found key was asked for
            missCount: 0,       # number of times a missing key was asked for
            evictionCount: 0,   # number of deletions on the cache
            expiredCount: 0,    # number of documents expired due to TTL
            creationDate: nil   # the date this cache was initialized

  @doc """
  Adds a number of evictions to the stats container, defaulting to 1.
  """
  def add_eviction(state, amount \\ 1),
  do: increment_stat(state, [:evictionCount], amount)

  @doc """
  Adds a number of expirations to the stats container, defaulting to 1.
  """
  def add_expiration(state, amount \\ 1),
  do: increment_stat(state, [:opCount, :expiredCount], amount)

  @doc """
  Adds a number of hits to the stats container, defaulting to 1.
  """
  def add_hit(state, amount \\ 1),
  do: increment_stat(state, [:opCount, :hitCount], amount)

  @doc """
  Adds a number of misses to the stats container, defaulting to 1.
  """
  def add_miss(state, amount \\ 1),
  do: increment_stat(state, [:opCount, :missCount], amount)

  @doc """
  Adds a number of operations to the stats container, defaulting to 1.
  """
  def add_op(state, amount \\ 1),
  do: increment_stat(state, [:opCount], amount)

  @doc """
  Adds a number of sets to the stats container, defaulting to 1.
  """
  def add_set(state, amount \\ 1),
  do: increment_stat(state, [:opCount, :setCount], amount)

  @doc """
  Increments a stat in a container by a given number, defaulting to 1. If stats
  are disaled for the state, we short-circuit and return the unmodified state.

  This is used internally by all other shorthand functions. We allow for multiple
  fields to be passed in order to increment them in a single pass without recreating
  the the stats struct.

  In addition to the passed in counter, we also increment the operation counter,
  due to the fact that all counters represent an operation.
  """
  def increment_stat(_state, _field, _amount \\ 1)
  def increment_stat(%Cachex.Worker{ stats: nil } = state, _field, _amount), do: state
  def increment_stat(state, field, amount)
  when not is_list(field), do: increment_stat(state, [field], amount)
  def increment_stat(%Cachex.Worker{ stats: %{ } = stats } = state, fields, amount) do
    new_stats = Enum.reduce(fields, stats, fn(field, stats) ->
      Map.put(stats, field, Map.get(stats, field, 0) + amount)
    end)
    %Cachex.Worker{ state | stats: new_stats }
  end
  def increment_stat(state, _stat, _amount), do: state

  @doc """
  Finalizes the struct into a Map containing various fields we can deduce from
  the struct. The bonus fields are why we don't just return the struct - there's
  no need to store these in the struct all the time, they're only needed once.
  """
  def finalize(%__MODULE__{ } = stats_struct) do
    reqRates = case stats_struct.hitCount + stats_struct.missCount do
      0 -> %{ "requestCount": 0 }
      v ->
        cond do
          stats_struct.hitCount == 0 -> %{
            "requestCount": v,
            "hitRate": 0,
            "missRate": 100
          }
          stats_struct.missCount == 0 -> %{
            "requestCount": v,
            "hitRate": 100,
            "missRate": 0
          }
          true -> %{
            "requestCount": v,
            "hitRate": stats_struct.hitCount / v,
            "missRate": stats_struct.missCount / v
          }
        end
    end

    stats_struct
    |> Map.from_struct
    |> Map.merge(reqRates)
    |> Enum.sort(&(elem(&1, 0) > elem(&2, 0)))
    |> Enum.into(%{})
  end

  @doc """
  Merges together two stat structs, typically performing addition of both values,
  but otherwise based on some internal logic.

  This *can* be used by the end-user, but this module will remain undocumented as
  we don't want users to accidentally taint their statistics.
  """
  def merge(%__MODULE__{ } = a, %__MODULE__{ } = b) do
    [__struct__|fields] = Map.keys(a)

    Enum.reduce([:opCount|fields], a, fn(field, state) ->
      a_val = Map.get(a, field, 0)
      b_val = Map.get(b, field, 0)

      case field do
        :creationDate ->
          Map.put(state, field, a_val < b_val && a_val || b_val)
        _other_values ->
          Map.put(state, field, a_val + b_val)
      end
    end)
  end

end
