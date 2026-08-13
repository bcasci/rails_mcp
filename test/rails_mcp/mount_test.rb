# frozen_string_literal: true

require "test_helper"
require "mcp"
require "rack/test"
require "json"

# T5 / R6, R10 — `mount_mcp` mounts the official gem's stateless Rack transport so a
# registered set of tools is served over HTTP. These tests drive the built Rack app
# directly with rack-test (a real MCP JSON-RPC round-trip), using a real MCP::Tool
# subclass rather than a stub, per conventions.
class RailsMcp::MountTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    @registry = RailsMcp::Registry.new
    @registered_tool = Class.new(MCP::Tool) do
      tool_name "registered_read_only"
      def self.call(**_args)
        MCP::Tool::Response.new([{type: "text", text: "ok"}])
      end
    end
    @registry.register(@registered_tool)

    # allowed_hosts lets rack-test's default Host (example.org) through the SDK's
    # DNS-rebinding guard; in a real deploy the app's own host clears it.
    @app = RailsMcp.rack_app(registry: @registry, allowed_hosts: ["example.org"])
  end

  attr_reader :app

  def json_rpc(method, params = {}, id: 1)
    header "Content-Type", "application/json"
    header "Accept", "application/json, text/event-stream"
    post "/", JSON.generate(jsonrpc: "2.0", id: id, method: method, params: params)
    JSON.parse(last_response.body)
  end

  # R6: the mounted endpoint answers MCP JSON-RPC in-process.
  def test_rack_app_responds_to_tools_list
    body = json_rpc("tools/list")

    assert_equal 200, last_response.status
    assert body["result"]
  end

  # R6 + R10: tools/list returns only registered tools.
  def test_tools_list_returns_only_registered_tools
    body = json_rpc("tools/list")
    names = body.dig("result", "tools").map { |t| t["name"] }

    assert_equal ["registered_read_only"], names
  end

  # R10: a registered tool is callable.
  def test_tools_call_on_a_registered_tool_runs
    body = json_rpc("tools/call", {name: "registered_read_only", arguments: {}})

    assert_equal "ok", body.dig("result", "content", 0, "text")
  end

  # R6 + R10: tools/call on an unregistered tool is refused (allow-list).
  def test_tools_call_on_an_unregistered_tool_is_refused
    body = json_rpc("tools/call", {name: "not_registered", arguments: {}})

    assert body["error"], "expected an error for an unregistered tool"
    refute body["result"]
  end

  # R6: the transport is configured stateless (SDK stateless mode serves POST without
  # a prior initialize/session id). A stateful transport would 400 "Missing session ID".
  def test_transport_is_stateless
    body = json_rpc("tools/list")

    refute_equal(-32600, body.dig("error", "code"))
    assert_equal 200, last_response.status
  end

  # R6: mount_mcp is available as a routing helper on the Rails router mapper and
  # mounts the built Rack app at the given path.
  def test_mount_mcp_is_a_router_helper
    mapper = Object.new
    mapper.extend(RailsMcp::Mount::Router)
    mounted = {}
    mapper.define_singleton_method(:mount) { |arg| mounted.merge!(arg) }

    mapper.mount_mcp("/mcp", registry: @registry, allowed_hosts: ["example.org"])

    app, path = mounted.first
    assert_equal "/mcp", path
    assert_respond_to app, :call
  end
end
