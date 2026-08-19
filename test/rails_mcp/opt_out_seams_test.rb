# frozen_string_literal: true

require "test_helper"
require "mcp"

# T1 / R3, R6 — the escapes are supported, tested seams, not accidents. An app can
# drop straight to a raw `MCP::Tool` or hand a plain `tools:` array to `MCP::Server`
# without leaving the gem or being nannied (ADR-0007, ADR-0012). The plain array is
# now the primary model: the app owns the list it hands `MCP::Server` (ADR-0013).
# And the gem never auto-discovers a tool by subclassing (R6).
#
# These tests exercise the real `MCP::Server` JSON-RPC path (tools/list, tools/call)
# rather than stubbing, per docs/conventions.md — the escape has to work end to end.
class RailsMcp::OptOutSeamsTest < Minitest::Test
  def setup
    # Capture the gem's one audit event so we can assert a raw tool never emits it.
    @events = []
    @subscriber = ActiveSupport::Notifications.subscribe(RailsMcp::Instrumentation::EVENT) do |*args|
      @events << ActiveSupport::Notifications::Event.new(*args)
    end
  end

  def teardown
    ActiveSupport::Notifications.unsubscribe(@subscriber)
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

  # --- R6: a raw MCP::Tool in the served list runs unaudited ---

  # R6: a raw MCP::Tool in the served array is listable — it appears in tools/list on
  # a server built from a plain `tools:` array, exactly like a RailsMcp::Tool would.
  def test_raw_tool_is_listable
    result = serve([raw_tool], method: "tools/list")

    names = result[:result][:tools].map { |t| t[:name] }
    assert_includes names, "raw_ping"
  end

  # R6: a served raw tool runs — tools/call returns its result over the real server
  # path (it is a first-class callable, just outside the gem's pipeline).
  def test_raw_tool_runs_via_tools_call
    result = serve([raw_tool], method: "tools/call", params: {name: "raw_ping", arguments: {}})

    assert_equal [{type: "text", text: "pong"}], result[:result][:content]
  end

  # R6: a raw tool is OUTSIDE the gem pipeline — invoking it emits NO
  # `invoke.rails_mcp` audit event (the gem does not audit tools it does not own).
  def test_raw_tool_invocation_emits_no_audit_event
    serve([raw_tool], method: "tools/call", params: {name: "raw_ping", arguments: {}})

    assert_empty @events, "a raw MCP::Tool must not emit the gem's audit event"
  end

  # R6: opting out is silent — serving and running a raw tool produces NO warning or
  # error from the gem (document-only, no nannying; ADR-0007).
  def test_raw_tool_opt_out_produces_no_gem_warning
    out, err = capture_io do
      serve([raw_tool], method: "tools/call", params: {name: "raw_ping", arguments: {}})
    end

    assert_empty err, "the gem must not warn when an app opts out to a raw MCP::Tool"
    assert_empty out
  end

  # --- R3: a plain `tools:` array is the served allow-list ---

  # R3: a plain `tools: [...]` array passed straight to MCP::Server serves without any
  # gem registry — the app owns the list it hands the server (ADR-0013).
  def test_plain_tools_array_serves_the_allow_list
    result = serve([raw_tool], method: "tools/call", params: {name: "raw_ping", arguments: {}})

    assert_equal [{type: "text", text: "pong"}], result[:result][:content]
  end

  # R3: the served array IS the allow-list — a tools/call for a name not in the array
  # is refused by `mcp` ("Tool not found"), no gem code involved.
  def test_call_for_a_name_not_in_the_array_is_refused
    result = serve([raw_tool], method: "tools/call", params: {name: "not_listed", arguments: {}})

    refute_nil result[:error], "mcp must refuse a call for a name outside the served array"
  end

  # --- R1: registry and expose! removed from the gem ---

  # R1: no `RailsMcp::Registry`, `RailsMcp.registry`, `register`, `registered?`,
  # `ToolNameCollision`, or `expose!` symbol survives in the gem.
  def test_registry_and_expose_symbols_are_gone
    refute RailsMcp.const_defined?(:Registry),
      "RailsMcp::Registry must be removed (ADR-0013)"
    refute RailsMcp.const_defined?(:ToolNameCollision),
      "RailsMcp::ToolNameCollision must be removed (ADR-0013)"
    refute RailsMcp.respond_to?(:registry),
      "RailsMcp.registry must be removed (ADR-0013)"
    refute RailsMcp::Tool.respond_to?(:expose!),
      "the expose! macro must be removed (ADR-0013)"
  end

  # R1: `lib/` contains no registry/`expose!`/`ToolNameCollision` reference — the
  # standing machine-checkable constraint from ADR-0013.
  def test_lib_has_no_registry_or_expose_references
    lib = File.expand_path("../../lib/rails_mcp", __dir__)
    entry = File.expand_path("../../lib/rails_mcp.rb", __dir__)
    files = Dir.glob(File.join(lib, "**", "*.rb")) + [entry]

    offenders = files.select do |path|
      File.read(path).match?(/RailsMcp\.registry|RailsMcp::Registry|ToolNameCollision|\bexpose!/)
    end

    assert_empty offenders,
      "no registry/expose! reference may remain in lib/ (R1, ADR-0013); found in: #{offenders.join(", ")}"
  end

  # R1: the registry file is gone from lib/.
  def test_registry_file_is_deleted
    path = File.expand_path("../../lib/rails_mcp/registry.rb", __dir__)

    refute File.exist?(path), "lib/rails_mcp/registry.rb must be deleted (ADR-0013)"
  end

  # --- R6: no auto-discovery — no `inherited` hook in the gem source ---

  # R6: the gem source has no `inherited` hook (or any convention) that adds a tool to
  # a served list automatically — exposure is always the app naming the class in its
  # own list.
  def test_gem_source_has_no_inherited_auto_registration_hook
    lib = File.expand_path("../../lib/rails_mcp", __dir__)
    ruby_files = Dir.glob(File.join(lib, "**", "*.rb"))

    offenders = ruby_files.select { |path| File.read(path).match?(/def (self\.)?inherited\b/) }

    assert_empty offenders,
      "no `inherited` hook may auto-register tools (R6, ADR-0007); found in: #{offenders.join(", ")}"
  end
end
