# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

require_relative "../tasks/adr_check_lib"

# adr:check constraint gate (SEC-04, SEC-05; SPEC 0013 R4, R5).
#
# Drives the checker (RailsMcp::AdrCheck) against a throwaway fixture tree so each
# planted violation is asserted in isolation from the live source and from T1–T3's
# parallel edits. A clean fixture must pass; each forbidden form must fail.
class AdrCheckTest < Minitest::Test
  # Build a minimal fixture gem tree under `dir` with the given lib file body, and an
  # optional stamped template body. Returns the root dir.
  def fixture_tree(dir, lib_body:, template_body: nil)
    FileUtils.mkdir_p(File.join(dir, "lib", "rails_mcp"))
    File.write(File.join(dir, "lib", "rails_mcp", "sample.rb"), lib_body)
    if template_body
      tdir = File.join(dir, "lib", "generators", "rails_mcp", "install", "templates")
      FileUtils.mkdir_p(tdir)
      File.write(File.join(tdir, "sample.rb.tt"), template_body)
    end
    dir
  end

  def run_check(lib_body:, template_body: nil)
    Dir.mktmpdir do |dir|
      fixture_tree(dir, lib_body: lib_body, template_body: template_body)
      RailsMcp::AdrCheck.run(root: dir)
    end
  end

  def checks_hit(violations)
    violations.map { |v| v[:check] }.uniq
  end

  # R4: a clean tree passes (no violations).
  def test_clean_tree_has_no_violations
    body = <<~RUBY
      # frozen_string_literal: true
      module RailsMcp
        class Sample
          def call
            new.__send__(:invoke)
            User.find_by(api_token_digest: Digest::SHA256.hexdigest(token))
          end
        end
      end
    RUBY

    assert_empty run_check(lib_body: body)
  end

  # R5: bareword `.send(` on a receiver is a violation.
  def test_bareword_send_is_flagged
    body = "module RailsMcp; class S; def c; foo.send(params[:x]); end; end; end\n"
    violations = run_check(lib_body: body)
    assert_includes checks_hit(violations), "dynamic-dispatch"
  end

  # R5: `__send__` of a literal is NOT flagged (the two safe sites' fixed form).
  def test_underscore_send_is_not_flagged
    body = "module RailsMcp; class S; def c; obj.__send__(:invoke); end; end; end\n"
    assert_empty run_check(lib_body: body)
  end

  # R5: `constantize` is a violation.
  def test_constantize_is_flagged
    body = %(module RailsMcp; class S; def c; params[:klass].constantize; end; end; end\n)
    assert_includes checks_hit(run_check(lib_body: body)), "dynamic-dispatch"
  end

  # R5: `const_get` is a violation.
  def test_const_get_is_flagged
    body = "module RailsMcp; class S; def c; Object.const_get(x); end; end; end\n"
    assert_includes checks_hit(run_check(lib_body: body)), "dynamic-dispatch"
  end

  # R5: `public_send` on a receiver is a violation.
  def test_public_send_is_flagged
    body = "module RailsMcp; class S; def c; obj.public_send(y); end; end; end\n"
    assert_includes checks_hit(run_check(lib_body: body)), "dynamic-dispatch"
  end

  # R5: bareword `public_send` on implicit self (no leading dot) is a violation —
  # the natural form inside a tool's `perform`. (REVIEW.md:14 names public_send
  # unqualified.)
  def test_bareword_public_send_is_flagged
    body = "module RailsMcp; class S; def c; public_send(params[:m]); end; end; end\n"
    assert_includes checks_hit(run_check(lib_body: body)), "dynamic-dispatch"
  end

  # R5: a forbidden form NAMED only in a comment is not a violation (comments stripped).
  def test_forbidden_form_in_a_comment_is_not_flagged
    body = <<~RUBY
      module RailsMcp
        class S
          # do not use obj.send(x) or "X".constantize or public_send here
          def c
            :ok
          end
        end
      end
    RUBY
    assert_empty run_check(lib_body: body)
  end

  # R4: a raw credential store (find_by on a raw token column) is a violation.
  def test_raw_credential_store_is_flagged
    body = "module RailsMcp; class S; def c; User.find_by(api_token: token); end; end; end\n"
    assert_includes checks_hit(run_check(lib_body: body)), "credential"
  end

  # R4: the digest column form is NOT flagged (the secure taught recipe).
  def test_digest_lookup_is_not_flagged
    body = "module RailsMcp; class S; def c; User.find_by(api_token_digest: d); end; end; end\n"
    assert_empty run_check(lib_body: body)
  end

  # R4: logging a credential value is a violation.
  def test_logging_a_credential_is_flagged
    body = "module RailsMcp; class S; def c; Rails.logger.info(api_token); end; end; end\n"
    assert_includes checks_hit(run_check(lib_body: body)), "credential"
  end

  # R4: the credential grep also covers stamped templates.
  def test_credential_in_a_stamped_template_is_flagged
    clean_lib = "module RailsMcp; class S; def c; :ok; end; end; end\n"
    tt = "class McpController\n  def x; User.find_by(api_token: token); end\nend\n"
    violations = run_check(lib_body: clean_lib, template_body: tt)
    assert_includes checks_hit(violations), "credential"
  end

  # R4 (ADR-0004): a gem-side tenant reference is a violation.
  def test_tenant_reference_is_flagged
    body = "module RailsMcp; class S; def c; ActsAsTenant.current_tenant; end; end; end\n"
    assert_includes checks_hit(run_check(lib_body: body)), "policy-tenant"
  end

  # ADR-0004: a shard scoping call is a violation.
  def test_shard_reference_is_flagged
    body = "module RailsMcp; class S; def c; Model.connected_to(shard: :s) { }; end; end; end\n"
    assert_includes checks_hit(run_check(lib_body: body)), "policy-tenant"
  end

  # Debugger detection is standardrb's Lint/Debugger, not adr:check (removed as redundant).

  # Existing constraints preserved: eval-family is a violation.
  def test_eval_family_is_flagged
    body = "module RailsMcp; class S; def c; instance_eval(src); end; end; end\n"
    assert_includes checks_hit(run_check(lib_body: body)), "eval-family"
  end

  # R4/R5: the live gem tree passes the check (no bareword `.send(`, no leaks). This
  # ties the fixture-driven checks to the real source the task guards.
  def test_live_gem_tree_is_clean
    root = File.expand_path("..", __dir__)
    violations = RailsMcp::AdrCheck.run(root: root)
    assert_empty violations,
      "live gem source has adr:check violations: #{violations.map { |v| "#{v[:check]} #{v[:file]}:#{v[:line]}" }.join(", ")}"
  end
end
