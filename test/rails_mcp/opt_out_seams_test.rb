# frozen_string_literal: true

require "test_helper"
require "mcp"

# T2 / R4, R5 — the registry escapes are supported, tested seams, not accidents.
# An app can drop straight to a raw `MCP::Tool`, serve a per-endpoint registry, or
# hand a plain `tools:` array to `MCP::Server` without leaving the gem or being
# nannied (ADR-0007). And the gem never auto-discovers a tool by subclassing (R5).
#
# These tests exercise the real `MCP::Server` JSON-RPC path (tools/list, tools/call)
# rather than stubbing, per docs/conventions.md — the escape has to work end to end.
class RailsMcp::OptOutSeamsTest < Minitest::Test
  def setup
    # R4's raw-tool test registers on the shared default registry; isolate it.
    RailsMcp.registry.clear

    # Capture the gem's one audit event so we can assert a raw tool never emits it.
    @events = []
    @subscriber = ActiveSupport::Notifications.subscribe(RailsMcp::Instrumentation::EVENT) do |*args|
      @events << ActiveSupport::Notifications::Event.new(*args)
    end
  end

  def teardown
    ActiveSupport::Notifications.unsubscribe(@subscriber)
    RailsMcp.registry.clear
  end

  # A plain `MCP::Tool` (NOT a `RailsMcp::Tool`) — the escape hatch. It has no
  # `authorize`, no audit wrapping; its `call` just returns a result.
  def raw_tool
    Class.new(MCP::Tool) do
      tool_name "raw_ping"
      description "a raw MCP::Tool outside the gem pipeline"
      input_schema(properties: {}, required: [])
      def self.call(**_arguments)
        MCP::Tool::Response.new([{type: "text", text: "pong"}])
      end
    end
  end

  # Serve a set of tools on a real MCP::Server and return the parsed JSON-RPC result
  # of a request — the public path the generated controller uses.
  def serve(tools, method:, params: {})
    server = MCP::Server.new(name: "test", tools: tools, server_context: {user: :staff})
    server.handle({jsonrpc: "2.0", id: 1, method: method, params: params})
  end

  # --- R4: a raw MCP::Tool registers via ordinary `register`, runs unaudited ---

  # R4: a raw MCP::Tool goes on the allow-list through the ordinary `register` —
  # there is no separate `register_raw` or `unaudited:` flag (ADR-0007).
  def test_raw_tool_registers_via_ordinary_register
    tool = raw_tool

    assert_same tool, RailsMcp.registry.register(tool)
    assert RailsMcp.registry.registered?(tool)
  end

  # R4: a registered raw tool is listable — it appears in tools/list on a server
  # built from `RailsMcp.registry.tools`, exactly like a RailsMcp::Tool would.
  def test_raw_tool_is_listable
    RailsMcp.registry.register(raw_tool)

    result = serve(RailsMcp.registry.tools, method: "tools/list")

    names = result[:result][:tools].map { |t| t[:name] }
    assert_includes names, "raw_ping"
  end

  # R4: a registered raw tool runs — tools/call returns its result over the real
  # server path (it is a first-class callable, just outside the gem's pipeline).
  def test_raw_tool_runs_via_tools_call
    RailsMcp.registry.register(raw_tool)

    result = serve(
      RailsMcp.registry.tools,
      method: "tools/call",
      params: {name: "raw_ping", arguments: {}}
    )

    assert_equal [{type: "text", text: "pong"}], result[:result][:content]
  end

  # R4: a raw tool is OUTSIDE the gem pipeline — invoking it emits NO
  # `invoke.rails_mcp` audit event (the gem does not audit tools it does not own).
  def test_raw_tool_invocation_emits_no_audit_event
    RailsMcp.registry.register(raw_tool)

    serve(RailsMcp.registry.tools, method: "tools/call", params: {name: "raw_ping", arguments: {}})

    assert_empty @events, "a raw MCP::Tool must not emit the gem's audit event"
  end

  # R4: opting out is silent — registering and running a raw tool produces NO
  # warning or error from the gem (document-only, no nannying; ADR-0007).
  def test_raw_tool_opt_out_produces_no_gem_warning
    tool = raw_tool

    out, err = capture_io do
      RailsMcp.registry.register(tool)
      serve(RailsMcp.registry.tools, method: "tools/call", params: {name: "raw_ping", arguments: {}})
    end

    assert_empty err, "the gem must not warn when an app opts out to a raw MCP::Tool"
    assert_empty out
  end

  # --- R4: a per-endpoint registry serves only its own tools ---

  # R4: a per-endpoint `RailsMcp::Registry.new` is independent of `RailsMcp.registry`
  # — a tool on the default registry is not on the per-endpoint one.
  def test_per_endpoint_registry_is_isolated_from_the_default
    default_tool = raw_tool
    RailsMcp.registry.register(default_tool)

    endpoint_registry = RailsMcp::Registry.new

    refute endpoint_registry.registered?(default_tool)
    assert_empty endpoint_registry.tools
  end

  # R4: a server built from a per-endpoint registry lists only that registry's tools
  # — not tools on the process-wide default registry.
  def test_per_endpoint_registry_serves_only_its_own_tools
    RailsMcp.registry.register(raw_tool)

    endpoint_registry = RailsMcp::Registry.new
    endpoint_tool = Class.new(MCP::Tool) do
      tool_name "endpoint_only"
      description "served on one endpoint"
      input_schema(properties: {}, required: [])
      def self.call(**_arguments)
        MCP::Tool::Response.new([{type: "text", text: "ok"}])
      end
    end
    endpoint_registry.register(endpoint_tool)

    result = serve(endpoint_registry.tools, method: "tools/list")

    names = result[:result][:tools].map { |t| t[:name] }
    assert_equal ["endpoint_only"], names
  end

  # --- R4: a plain `tools:` array works without any RailsMcp::Registry ---

  # R4: a plain `tools: [...]` array passed straight to MCP::Server serves without
  # `RailsMcp.registry` at all — the registry is a convenience, not a requirement.
  def test_plain_tools_array_serves_without_the_registry
    tool = raw_tool

    result = serve([tool], method: "tools/call", params: {name: "raw_ping", arguments: {}})

    assert_equal [{type: "text", text: "pong"}], result[:result][:content]
    assert_empty RailsMcp.registry.tools, "the default registry was never involved"
  end

  # --- R5: no auto-discovery — no `inherited` hook in the gem source ---

  # R5: the gem source has no `inherited` hook (or any convention) that adds a tool
  # to a registry automatically — exposure is always an explicit register/expose!.
  def test_gem_source_has_no_inherited_auto_registration_hook
    lib = File.expand_path("../../lib/rails_mcp", __dir__)
    ruby_files = Dir.glob(File.join(lib, "**", "*.rb"))

    offenders = ruby_files.select { |path| File.read(path).match?(/def (self\.)?inherited\b/) }

    assert_empty offenders,
      "no `inherited` hook may auto-register tools (R5, ADR-0007); found in: #{offenders.join(", ")}"
  end

  # R5: defining a RailsMcp::Tool subclass has no effect on any registry — a fresh
  # per-endpoint registry stays empty even after a subclass is defined (subclassing
  # is never a registration act).
  def test_defining_a_subclass_registers_nothing
    endpoint_registry = RailsMcp::Registry.new

    Class.new(RailsMcp::Tool) { tool_name "defined_not_exposed" }

    assert_empty endpoint_registry.tools
    assert_empty RailsMcp.registry.tools
  end
end
