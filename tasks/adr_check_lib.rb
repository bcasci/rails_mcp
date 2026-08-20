# frozen_string_literal: true

module RailsMcp
  # The constraint checker behind `rake adr:check` (SEC-04, SEC-05).
  #
  # Plain Ruby (no gem runtime dependency) so it lives OUTSIDE `lib/` — it is a
  # development/CI tool, not shipped in `spec.files`, and keeping it out of `lib/`
  # means its own regex literals (which necessarily contain `.send(`, `constantize`,
  # `token`, etc.) are not scanned by the very checks they define.
  #
  # `run(root:)` scans the gem's source and stamped templates and returns a list of
  # violations (each a Hash with :check, :file, :line, :text). An empty list means a
  # clean tree. Comments are stripped before matching so a teaching comment that
  # merely NAMES a forbidden form (e.g. the template documenting the old insecure
  # recipe) is not itself a violation — only live code counts.
  module AdrCheck
    # Named checks. Each: a human name, the patterns that constitute a violation, and
    # the file set the check applies to (`:lib` = gem Ruby under lib/; `:credentialed`
    # = lib/ plus stamped generator templates).
    CHECKS = [
      {
        name: "debugger",
        scope: :lib,
        patterns: [/binding\.(?:pry|irb)/]
      },
      {
        name: "eval-family",
        scope: :lib,
        # instance_eval / class_eval / Kernel.eval / a bareword eval( that is not a
        # method call on a receiver.
        patterns: [/\b(?:instance_eval|class_eval|Kernel\.eval)\(/, /(?<![.\w])eval\(/]
      },
      {
        name: "dynamic-dispatch",
        scope: :lib,
        # The forms an app tool would use to turn an AI-supplied string into a class
        # or method (SEC-05). Bareword `.send(` is forbidden — the two known-safe
        # fixed-symbol sites use `__send__` (tool.rb:43, args.rb:119).
        patterns: [
          /\.constantize\b/,
          /\bconst_get\b/,
          /\.public_send\b/,
          /\.send\(/
        ]
      },
      {
        name: "credential",
        scope: :credentialed,
        # A token/secret/bearer/password/api_key VALUE being logged or stored/compared
        # raw in gem or stamped code (SEC-04). Two shapes:
        #   - logged: a logger/puts/print/warn call that names a credential
        #   - stored raw: find_by / where on a raw credential column (a digest column
        #     ends in _digest and is NOT matched)
        patterns: [
          /(?:Rails\.logger|logger|puts|print|warn|p)\b[^#]*\b(?:api_token|bearer_token|password|secret|api_key)\b/,
          /find_by\(\s*(?:api_token|password|secret|api_key)\s*:/,
          /where\(\s*(?:api_token|password|secret|api_key)\s*:/
        ]
      },
      {
        name: "policy-tenant",
        scope: :lib,
        # Gem-side policy/tenant/shard machinery (ADR-0004 — the gem owns zero policy
        # and has no tenant concept). Identifiers that never legitimately appear as gem
        # runtime code; teaching comments naming Pundit are stripped before matching.
        patterns: [
          /\b(?:acts_as_tenant|ActsAsTenant|current_tenant|tenant_id|switch_tenant|Apartment::Tenant)\b/,
          /\.on_shard\b/,
          /\bconnected_to\(\s*shard:/
        ]
      }
    ].freeze

    module_function

    # Scan the tree at `root` and return violations (empty = clean).
    def run(root:)
      violations = []
      CHECKS.each do |check|
        files_for(check[:scope], root).each do |path|
          scan_file(path, check, violations)
        end
      end
      violations
    end

    def files_for(scope, root)
      lib = File.join(root, "lib")
      case scope
      when :lib
        Dir.glob(File.join(lib, "**", "*.rb")) + template_files(root)
      when :credentialed
        Dir.glob(File.join(lib, "**", "*.rb")) + template_files(root)
      else
        []
      end
    end

    # Stamped generator templates (.tt) — copied verbatim into an app, so they are
    # part of the taught/credentialed surface.
    def template_files(root)
      Dir.glob(File.join(root, "lib", "generators", "**", "templates", "**", "*"))
        .select { |p| File.file?(p) }
    end

    def scan_file(path, check, violations)
      File.foreach(path).with_index(1) do |line, lineno|
        code = strip_comment(line)
        next if code.strip.empty?

        check[:patterns].each do |pat|
          next unless code.match?(pat)

          violations << {check: check[:name], file: path, line: lineno, text: line}
          break
        end
      end
    end

    # Remove a Ruby comment from a line so a forbidden form NAMED in a comment is not a
    # violation. Full-line comments become empty; an inline `#` is dropped only when it
    # is not inside a string literal (an even number of unescaped quotes precede it).
    def strip_comment(line)
      idx = comment_index(line)
      idx ? line[0...idx] : line
    end

    def comment_index(line)
      in_single = false
      in_double = false
      i = 0
      while i < line.length
        ch = line[i]
        case ch
        when "\\"
          i += 2
          next
        when "'"
          in_single = !in_single unless in_double
        when '"'
          in_double = !in_double unless in_single
        when "#"
          return i unless in_single || in_double
        end
        i += 1
      end
      nil
    end
  end
end
