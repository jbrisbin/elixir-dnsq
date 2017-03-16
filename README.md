# Dynamic MQTT-based DNS server

`DNSQ` is an Elixir application that connects to an MQTT broker and responds to messages sent to `dnsq/$zone` where `$zone` is the name of a DNS "zome" (usually a domain name). The content of the message contains lines of text containing a command, followed by a space-separated list of arguments to that command which take the following form:

```
add host A 0 10.1.1.1
```

The fields are:

1) Command. One of `add`, `update`, or `remove`
2) Host. Unqualified hostname that will be combined with the value of zone extracted from the topic.
3) DNS record type. One of `A`, `CNAME`, `TXT`, or `PTR`.
4) TTL. Value of the time-to-live.
5) Data. Value of the record, which could be an IP address or a hostname or a set of `key=value` pairs for the `TXT` record type.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `dnsq` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:dnsq, "~> 0.1.0"}]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/dnsq](https://hexdocs.pm/dnsq).

