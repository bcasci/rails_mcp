# frozen_string_literal: true

require "test_helper"
require "mcp"

# T4 — RailsMcp::Tool base class (SPEC R2, R3). The class the SDK invokes via
# `call(**args, server_context:)`; it wraps every invocation as
# authorize -> perform -> notify, fails closed by default, and offers the
# text_response helper. Args (T1) and Annotations (T2) are mixed in; the audit
# event (T3) fires exactly once per invoke, including on raise.
class RailsMcp::ToolTest < Minitest::Test
  def setup
    @events = []
    @subscriber = ActiveSupport::Notifications.subscribe(RailsMcp::Instrumentation::EVENT) do |*args|
      @events << ActiveSupport::Notifications::Event.new(*args)
    end
  end

  def teardown
    ActiveSupport::Notifications.unsubscribe(@subscriber)
  end

  # A staff user stand-in the app would resolve and place in server_context.
  def user(id: 1)
    Struct.new(:id).new(id)
  end

  # A tool that authorizes anyone and echoes its declared arg. `perform` is the
  # convention (R2); `authorize` is overridden to allow so the happy path runs.
  def echo_tool
    Class.new(RailsMcp::Tool) do
      tool_name "echo"
      arg :household_id, :integer, required: true

      def authorize(**)
        true
      end

      def perform(household_id:)
        text_response("household #{household_id}")
      end
    end
  end

  def context(staff = user)
    {user: staff}
  end

  # --- R2: perform convention + result ---

  # R2: perform receives declared args as keywords and its return value is the
  # tool result surfaced to the client.
  def test_perform_receives_declared_args_and_returns_result
    response = echo_tool.call(household_id: 42, server_context: context)

    assert_equal [{type: "text", text: "household 42"}], response.content
  end

  # R2: text_response("ok") yields a text content result equal to "ok".
  def test_text_response_yields_text_content
    klass = Class.new(RailsMcp::Tool) do
      tool_name "greet"
      def authorize(**) = true
      def perform(**) = text_response("ok")
    end

    response = klass.call(server_context: context)

    assert_instance_of MCP::Tool::Response, response
    assert_equal [{type: "text", text: "ok"}], response.content
  end

  # R1 allow-list on args: an undeclared argument is dropped before perform, so
  # perform never sees it (guards against the AI smuggling arbitrary args).
  def test_undeclared_args_are_not_forwarded_to_perform
    seen = nil
    klass = Class.new(RailsMcp::Tool) do
      tool_name "capture"
      arg :household_id, :integer
      define_method(:authorize) { |**| true }
      define_method(:perform) do |**args|
        seen = args
        text_response("done")
      end
    end

    klass.call(household_id: 1, injected: "evil", server_context: context)

    assert_equal({household_id: 1}, seen)
  end

  # --- R3: authorize fail-closed seam ---

  # R3: a tool whose authorize is not overridden is denied, and perform never runs.
  def test_default_authorize_fails_closed_and_perform_never_runs
    ran = false
    klass = Class.new(RailsMcp::Tool) do
      tool_name "unguarded"
      define_method(:perform) { |**| ran = true }
    end

    assert_raises(RailsMcp::NotAuthorized) do
      klass.call(server_context: context)
    end
    refute ran, "perform must not run when authorize denies"
  end

  # R3: when the app's authorize raises (failed check), perform never runs.
  def test_authorize_that_raises_blocks_perform
    ran = false
    klass = Class.new(RailsMcp::Tool) do
      tool_name "guarded"
      define_method(:authorize) { |**| raise RailsMcp::NotAuthorized, "nope" }
      define_method(:perform) { |**| ran = true }
    end

    assert_raises(RailsMcp::NotAuthorized) do
      klass.call(server_context: context)
    end
    refute ran, "perform must not run when authorize raises"
  end

  # R3: authorize passing lets perform run.
  def test_authorize_passing_runs_perform
    response = echo_tool.call(household_id: 7, server_context: context)

    assert_equal [{type: "text", text: "household 7"}], response.content
  end

  # R3: authorize runs before perform, receiving the frozen context contract
  # user:/args:/tool: (tool: is the invoked tool instance).
  def test_authorize_receives_user_args_and_tool
    seen = {}
    staff = user(id: 99)
    klass = Class.new(RailsMcp::Tool) do
      tool_name "inspect_ctx"
      arg :household_id, :integer
      define_method(:authorize) do |user:, args:, tool:|
        seen[:user] = user
        seen[:args] = args
        seen[:tool] = tool
        true
      end
      def perform(**) = text_response("ok")
    end

    klass.call(household_id: 3, server_context: {user: staff})

    assert_same staff, seen[:user]
    assert_equal({household_id: 3}, seen[:args])
    assert_instance_of klass, seen[:tool]
  end

  # --- R3/R4: Tool-specific wiring around the audit event ---
  #
  # Ownership split (SPEC R5): the event-count and payload-shape contract
  # (exactly one event per invoke, the frozen `user`/`tool`/`args`/`result`|`error`
  # payload keys) is owned by `instrumentation_test.rb`. The Tool tests here assert
  # only the wiring — that `authorize` runs inside the single event, including the
  # denial-before-`perform` path — not the payload shape or the success/failure counts.

  # R4/R3: the deny path still emits exactly one event, recording the error — the
  # denial-before-`perform` wiring proof (authorize failure is still audited once).
  def test_authorize_denial_emits_exactly_one_event_with_error
    klass = Class.new(RailsMcp::Tool) { tool_name "denied" }

    assert_raises(RailsMcp::NotAuthorized) do
      klass.call(server_context: context)
    end

    assert_equal 1, @events.length
    assert_instance_of RailsMcp::NotAuthorized, @events.first.payload[:error]
  end

  # --- RailsMcp::Tool boundary: the gem's guarantees are scoped to its own tools ---
  #
  # R9 (ADR-0004, ADR-0013): the authorize/audit guarantees live in `RailsMcp::Tool.call`.
  # A raw `MCP::Tool` served straight on `MCP::Server` is OUTSIDE that boundary — the gem
  # neither wraps nor audits a tool it does not own. The served `tools:` array is itself the
  # allow-list (the app owns the list it hands `MCP::Server`). These exercise the real
  # `MCP::Server` JSON-RPC path rather than stubbing, per docs/conventions.md.

  # A plain `MCP::Tool` (NOT a `RailsMcp::Tool`) — the escape hatch. No `authorize`, no
  # audit wrapping; its `call` just returns a result.
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

  # Serve a set of tools on a real MCP::Server and return the parsed JSON-RPC result.
  def serve(tools, method:, params: {})
    server = MCP::Server.new(name: "test", tools: tools, server_context: {user: :staff})
    server.handle({jsonrpc: "2.0", id: 1, method: method, params: params})
  end

  # R9 (ADR-0004): a raw `MCP::Tool` served on `MCP::Server` runs unaudited — it is not a
  # `RailsMcp::Tool`, so `RailsMcp::Tool.call` never wraps it and no `invoke.rails_mcp`
  # event fires. The gem's audit boundary is its own Tool, not any served tool.
  def test_raw_mcp_tool_runs_unaudited_outside_the_tool_boundary
    result = serve([raw_tool], method: "tools/call", params: {name: "raw_ping", arguments: {}})

    assert_equal [{type: "text", text: "pong"}], result[:result][:content]
    assert_empty @events, "a raw MCP::Tool is outside RailsMcp::Tool and must not emit the audit event"
  end

  # R9 (ADR-0013): the plain `tools:` array handed to `MCP::Server` IS the allow-list —
  # a `tools/call` for a name not in the served array is refused by `mcp`, no gem code
  # involved. The app owns the callable surface by naming classes in its own list.
  def test_served_tools_array_is_the_allow_list
    listed = serve([echo_tool], method: "tools/call",
      params: {name: "echo", arguments: {household_id: 5}})
    assert_equal [{type: "text", text: "household 5"}], listed[:result][:content]

    refused = serve([echo_tool], method: "tools/call",
      params: {name: "not_listed", arguments: {}})
    refute_nil refused[:error], "mcp must refuse a call for a name outside the served array"
  end

  # --- mixins present (T1 args, T2 annotations wired into the base class) ---

  # R1: the args DSL is available on subclasses and builds the input schema.
  def test_arg_dsl_contributes_to_input_schema
    schema = echo_tool.input_schema.to_h

    assert_equal "integer", schema[:properties][:household_id][:type]
    assert_includes schema[:required], "household_id"
  end

  # R5: the annotations DSL is available; read_only! sets readOnlyHint.
  def test_read_only_annotation_available
    klass = Class.new(RailsMcp::Tool) do
      tool_name "ro"
      read_only!
    end

    assert_equal true, klass.to_h[:annotations][:readOnlyHint]
  end

  # R9: with no user resolved in context, authorize still receives user: nil and
  # the gem does not invent an identity (fail-closed is the app's authorize job).
  def test_missing_user_is_passed_as_nil_not_invented
    seen = :unset
    klass = Class.new(RailsMcp::Tool) do
      tool_name "nouser"
      define_method(:authorize) do |user:, **|
        seen = user
        true
      end
      def perform(**) = text_response("ok")
    end

    klass.call(server_context: {})

    assert_nil seen
  end
end
