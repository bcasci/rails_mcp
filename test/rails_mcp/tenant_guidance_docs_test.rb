# frozen_string_literal: true

require "test_helper"

# T2 / R3 (tool-note half), R4 — the tenant/shard guidance is corrected. Scoping a
# multi-tenant app belongs at the CONTROLLER wrapping `handle_request` (so both
# `authorize` and `perform` run in-shard), not inside `perform` only. The stamped
# `ApplicationMcpTool` note points there; the docs carry a tenant-safe canonical
# example and explain recovering the tenant in the synchronous audit subscriber.
#
# These assert on the actual stamped template and the shipped docs (the source of
# truth an implementor reads), one criterion per test.
class RailsMcp::TenantGuidanceDocsTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  TEMPLATE = File.join(
    ROOT,
    "lib/generators/rails_mcp/install/templates/application_mcp_tool.rb.tt"
  )
  USAGE = File.join(ROOT, "docs/USAGE.md")
  SEAMS = File.join(ROOT, "docs/SEAMS.md")

  def template = File.read(TEMPLATE)

  def usage = File.read(USAGE)

  def seams = File.read(SEAMS)

  # The tenant note's prose (comment lines only) — where the correction lives.
  def template_tenant_note
    template.lines
      .select { |l| l.strip.start_with?("#") }
      .join
      .downcase
  end

  # --- R3 (ApplicationMcpTool tenant note) -------------------------------------

  # R3: the tenant note points to the CONTROLLER (wrapping handle_request) as the
  # correct scoping layer — not perform-only.
  def test_tenant_note_points_to_controller_wrapping_handle_request
    note = template_tenant_note
    assert_includes note, "controller",
      "the tenant note must point to the controller as the scoping layer"
    assert_includes note, "handle_request",
      "the tenant note must name wrapping handle_request as the scoping site"
  end

  # R3: the note explains that `authorize` also needs the shard (the reason
  # perform-only scoping is wrong: authorize runs before perform).
  def test_tenant_note_explains_authorize_also_needs_the_shard
    note = template_tenant_note
    assert_includes note, "authorize",
      "the tenant note must explain that authorize also runs in-shard"
  end

  # R3: the note no longer advises scoping ONLY inside perform. The old
  # `perform`/`with_shard { super }` example that scoped perform alone is gone.
  def test_tenant_note_no_longer_advises_perform_only_scoping
    refute_match(/with_shard\s*\{\s*super\s*\}/, template,
      "the perform-only `with_shard { super }` example must be removed — " \
      "scoping perform alone leaves authorize out of shard")
  end

  # R11 (no regression): the corrected note is still a COMMENT — no active
  # tenant/shard code is stamped into the app by default.
  def test_no_active_tenant_code_is_stamped
    code_lines = template.lines.reject do |l|
      l.strip.empty? || l.strip.start_with?("#")
    end
    refute(code_lines.any? { |l| l.include?("with_shard") },
      "no active with_shard code may be stamped (R11: no presumed tenancy)")
  end

  # --- R4 (safe canonical example + tenant-in-audit docs) ----------------------

  # R4: USAGE.md's canonical tool example queries through the tenant / a scoped
  # relation, or explicitly flags an unscoped global find as unsafe for multitenant.
  def test_usage_canonical_example_is_tenant_safe_or_flags_unsafe_find
    doc = usage.downcase
    scoped = doc.include?("current_tenant") || doc.include?("scoped") ||
      doc.include?("with_shard")
    flagged = doc.include?("unscoped") &&
      (doc.include?("unsafe") || doc.include?("multitenant") || doc.include?("multi-tenant"))
    assert(scoped || flagged,
      "USAGE.md must show a tenant-scoped canonical example or explicitly flag an " \
      "unscoped global find as unsafe for multitenant apps")
  end

  # R4: USAGE.md gives controller-level with_shard guidance (scoping at the
  # controller wrapping handle_request), consistent with R3.
  def test_usage_gives_controller_level_with_shard_guidance
    doc = usage
    # The wrap must show with_shard around handle_request together on one line —
    # the controller-level wrap, not two unrelated mentions.
    assert_match(/with_shard\b.*handle_request\(request\)/, doc,
      "USAGE.md tenancy guidance must show with_shard wrapping handle_request(request) " \
      "at the controller")
  end

  # R4: the docs explain the tenant is recoverable in the invoke.rails_mcp
  # subscriber via Current (it runs synchronously on the request thread), since the
  # frozen payload carries no tenant.
  def test_docs_explain_tenant_recoverable_in_subscriber_via_current
    combined = (usage + seams).downcase
    assert_includes combined, "current",
      "the docs must explain the tenant is recoverable in the subscriber via Current"
    assert(combined.include?("synchronous") || combined.include?("synchronously") ||
      combined.include?("request thread"),
      "the docs must state the subscriber runs synchronously on the request thread")
  end

  # R4: SEAMS.md keeps the frozen fact that the payload carries no tenant by design
  # (the reason recovery via Current is needed), no regression.
  def test_seams_states_payload_carries_no_tenant_by_design
    doc = seams.downcase
    assert_includes doc, "no tenant",
      "SEAMS.md must keep the frozen fact that the payload carries no tenant"
  end
end
