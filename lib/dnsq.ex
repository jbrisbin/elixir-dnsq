defmodule DNSQ do
  require Logger
  @moduledoc """
  Documentation for DNSQ.
  """

  def canonicalize(fqdn) when is_binary(fqdn) do
    fqdn = case String.ends_with?(fqdn, ".") do
      true -> fqdn
      false -> fqdn <> "."
    end
    Enum.join(Enum.reverse(String.split(fqdn, ".")), ".")
  end

  def canonicalize(domain, host) do
    canonicalize(host <> "." <> domain)
  end  

  def canonicalize(domain, host, service) do
    canonicalize(service <> "." <> host <> "." <> domain)
  end  
  
  @doc """
  Hello world.

  ## Examples

      iex> DNSQ.hello
      :world

  """
  def load(path, opts \\ [create_if_missing: true]) do
    db_dir = Application.get_env(:dnsq, :db_dir, "/var/lib/dnsq")
    {:ok, db} = Exleveldb.open(db_dir, opts)
    {:ok, f} = File.read path
    zone = path |> Path.basename |> Path.rootname
    try do
      for line <- String.split(f, "\n") do
        case line |> String.split do
          [host, type, ttl | data] -> 
            type_a = to_a(type)
            ttl = to_i(ttl)
            load_line(db, zone, host, type_a, data, ttl)
          _ -> :pass
        end
      end
    after
      :ok = Exleveldb.close db
    end
  end
  
  def put(db, zone, host, type, data, ttl \\ 0) do
    type_s = to_string(to_a(type))
    key = canonicalize(zone, host) <> "." <> type_s
    Logger.debug "PUT: #{inspect key} = #{inspect {ttl, data}}"
    :ok = Exleveldb.put(db, key, :erlang.term_to_binary({ttl, data}))
  end

  def get(db, zone, host, type) do
    get(db, host <> "." <> zone, type)
  end

  def get(db, fqdn, type) do
    type_s = upcase(type)
    key = canonicalize(fqdn) <> "." <> type_s
    Logger.debug "GET: #{key}"

    case Exleveldb.get(db, key) do
      {:ok, value}  -> 
        {ttl, data} = :erlang.binary_to_term(value)
        {:ok, ttl, data}
      _             -> 
        {:error, :not_found}
    end
  end

  def remove(db, zone, host, type) do
    type_s = to_string(to_a(type))
    key = canonicalize(zone, host) <> "." <> type_s
    :ok = Exleveldb.delete(db, key)
  end

  def fold(db, fqdn) do
    {:ok, iter} = Exleveldb.iterator(db)
    prefix = canonicalize(fqdn)
    results = try do
      next_record = Exleveldb.iterator_move(iter, prefix)
      advance(next_record, prefix, [], iter)
    after
      :ok = Exleveldb.iterator_close(iter)
    end
    Logger.debug "found results: #{inspect results}"
    results
  end

  def load_line(db, zone, host, :A, [addr], ttl) do
    Logger.debug "handle A record #{host}.#{zone} :: #{inspect addr}"
    ip = List.to_tuple(Enum.map(String.split(addr, "."), fn i -> to_i(i) end))
    put(db, zone, host, :A, ip, ttl)
  end

  def load_line(db, zone, host, :PTR, [domain], ttl) do
    Logger.debug "handle PTR record #{host}.#{zone} :: #{inspect domain}"
    put(db, zone, host, :PTR, to_c(domain), ttl)
  end

  def load_line(db, zone, host, :CNAME, [cname], ttl) do
    Logger.debug "handle CNAME record #{host}.#{zone} :: #{inspect cname}"
    put(db, zone, host, :CNAME, to_c(cname), ttl)
  end

  def load_line(db, zone, host, :SRV, [prio, wght, port, tgt] = record, ttl) do
    Logger.debug "handle SRV record #{host}.#{zone} :: #{inspect record}"
    data = {
      to_i(prio), 
      to_i(wght), 
      to_i(port), 
      to_c(tgt)
    }
    put(db, zone, host, :SRV, data, ttl)
  end

  def load_line(db, zone, host, :TXT, capabilities, ttl) do
    Logger.debug "handle TXT record #{host}.#{zone} :: #{inspect capabilities}"
    put(db, zone, host, :TXT, String.to_charlist(Enum.join(capabilities, " ")), ttl)
  end

  defp advance({:ok, k, v}, prefix, results, iter) do
    case String.starts_with?(k, prefix) do
      true -> 
        [type | host] = String.split(k, ".") |> Enum.reverse
        {ttl, data} = :erlang.binary_to_term(v)
        advance(
          Exleveldb.iterator_move(iter, :next),
          prefix,
          results ++ [{Enum.join(host, "."), to_a(type), ttl, data}],
          iter
        )
      false ->
        results
    end
  end

  defp advance({:error, _}, _prefix, results, _iter) do
    results
  end

  defp to_a(s) do
    s |> upcase |> String.to_atom
  end

  defp to_c(s) do
    String.to_charlist(s)
  end

  defp to_i(s) do
    String.to_integer(s)
  end

  defp upcase(s) do
    s |> to_string |> String.upcase
  end

end
