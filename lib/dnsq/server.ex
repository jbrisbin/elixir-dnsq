defmodule DNSQ.Server do
  use GenServer
  require Logger

  def start_link do
    GenServer.start_link(__MODULE__, [], name: :server)
  end

  def init([]) do
    port = Application.get_env(:dnsq, :listen_port, 5553)
    {:ok, server} = :gen_udp.open(port)
    :gen_udp.controlling_process(server, self())

    db_dir = Application.get_env(:dnsq, :db_dir, "/var/lib/dnsq")
    {:ok, db} = Exleveldb.open(db_dir)

    topic_prefix = Application.get_env(:dnsq, :topic_prefix, "dnsq")

    [hostname, port] = String.split(Application.get_env(:dnsq, :broker, "localhost:1883"), ":")
    connect_opts = [
      {:host, String.to_charlist(hostname)},
      {:port, String.to_integer(port)},
      {:client_id, "dnsq"},
      {:keepalive, 0},
      {:logger, {:console, :info}},
      {:clean_sess, false}
    ]
    {:ok, client} = :emqttc.start_link(connect_opts)

    {:ok, %{
      db: db,
      topic_prefix: topic_prefix,
      client: client
    }}
  end

  def handle_info({:query, name, type} = msg, %{:db => db} = state) do
    answer = DNSQ.get(db, name, String.to_atom(String.upcase(type)))
    Logger.debug "handle query: #{inspect msg} #{inspect answer}"
    {:noreply, state}
  end

  def handle_info({:udp, socket, ip, port, msg}, state) do
    record = DNS.Record.decode(IO.iodata_to_binary(msg))
    Logger.debug "query: #{inspect record}"
    
    answers = handle_query(record.qdlist, state)
    Logger.debug "answers: #{inspect answers}"
    response = DNS.Record.encode(%{record | anlist: answers})
    :gen_udp.send(socket, ip, port, response)

    {:noreply, state}
  end

  def handle_info({:publish, topic, msg}, state) do
    Logger.debug "got update message: #{topic} #{inspect msg}"
    topic_x = String.split(topic, "/")
    state = handle_update(topic_x, msg, state)
    {:noreply, state}
  end
  
  def handle_info({:mqttc, client, :connected}, %{:topic_prefix => topic_prefix} = state) do
    Logger.debug "connected: #{inspect client}"
    :ok = :emqttc.subscribe(client, "#{topic_prefix}/#", :qos1)
    {:noreply, state}
  end 

  def handle_info({:mqttc, client, :disconnected}, state) do
    Logger.debug "disconnected: #{inspect client}"
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug "handle_info: #{inspect msg}"
    {:noreply, state}
  end

  def terminate(reason, %{:db => db} = state) do
    Logger.error "terminating because #{inspect reason}"
    :ok = Exleveldb.close(db)
    :normal
  end

  def terminate(reason, state) do
    Logger.error "terminating because #{inspect reason} but can't close DB!'"
    {:shutdown, :cant_close_db}
  end

  defp handle_update([prefix, zone], msg, state) do
    for line <- String.split(msg, "\n") do
      case line |> String.split do
        [upd_type, host, rec_type, ttl | data] -> 
          upd_type_a = String.to_atom(upd_type)
          ttl = String.to_integer(ttl)
          rec_type_a = String.to_atom(String.upcase(rec_type))
          :ok = do_update(upd_type_a, zone, host, rec_type_a, ttl, data, state)
        _ -> :pass
      end
    end
    state
  end

  defp handle_query(queries, state) do
    handle_query(queries, [], state)
  end

  defp handle_query([], results, state) do
    results
  end

  defp handle_query([q | rest], results, %{:db => db} = state) do
    answer = case DNSQ.get(db, to_string(q.domain), q.type) do
      {:ok, ttl, data} -> results ++ [make_record(q.domain, q.type, ttl, data)]
      _ -> results
    end
    Logger.debug "found answer: #{inspect answer}"
    handle_query(rest, answer, state)
  end
  
  defp make_record(domain, type, ttl, data) do
    %DNS.Resource{
      domain: domain,
      class: :in,
      type: type,
      ttl: ttl,
      data: data
    }
  end

  defp do_update(:add, zone, host, rec_type, ttl, data, %{:db => db} = state) do
    :ok = DNSQ.load_line(db, zone, host, rec_type, data, ttl)
  end

  defp do_update(:update, zone, host, rec_type, ttl, data, %{:db => db} = state) do
    :ok = DNSQ.load_line(db, zone, host, rec_type, data, ttl)
  end

  defp do_update(:remove, zone, host, rec_type, ttl, data, %{:db => db} = state) do
    :ok = DNSQ.remove(db, zone, host, rec_type)
  end
  
end