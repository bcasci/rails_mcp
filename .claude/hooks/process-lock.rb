#!/usr/bin/env ruby

# Process-lock hook — PreToolUse(Bash). Denies the one local action that would
# bypass the pre-commit quality gate: `--no-verify` / `git commit -n`.
#
# Matching is token-based (Shellwords): a quoted argument such as a commit
# message that merely mentions `--no-verify` is one token and does not trip the
# lock (zero false-positives on real work).
#
# Additive and self-contained: remove the settings.json wiring and prior behavior
# is fully restored.

require "json"
require "shellwords"

class ProcessLock
  # A single-dash short-flag token containing `n` (e.g. `-n`, `-nm`) — the short
  # alias for `git commit --no-verify`.
  SHORT_N_FLAG = /\A-[a-zA-Z]*n[a-zA-Z]*\z/

  NO_VERIFY_DENIAL = "Process lock: --no-verify skips the pre-commit quality gate " \
                     "(standardrb + tests). Fix the offenses instead of bypassing the gate.".freeze
  COMMIT_SHORT_N_DENIAL = "Process lock: `git commit -n` is --no-verify and skips the pre-commit " \
                          "quality gate. Fix the offenses instead of bypassing the gate.".freeze

  def self.call(raw_input)
    new(raw_input).call
  end

  def initialize(raw_input)
    @data = parse(raw_input)
  end

  def call
    return unless @data["tool_name"] == "Bash"

    command = @data.dig("tool_input", "command").to_s
    return if command.strip.empty?

    reason = denial_reason(tokenize(command))
    deny(reason) if reason
  end

  private

  def parse(raw_input)
    JSON.parse(raw_input)
  rescue JSON::ParserError
    {}
  end

  # Quotes are respected, so a quoted message is one token. On a parse error
  # (unbalanced quotes) fall back to a naive split — conservative, since a
  # guardrail should err toward catching the dangerous action.
  def tokenize(command)
    Shellwords.split(command)
  rescue ArgumentError
    command.split(/\s+/)
  end

  def denial_reason(tokens)
    return NO_VERIFY_DENIAL if tokens.include?("--no-verify")
    return COMMIT_SHORT_N_DENIAL if commit_short_no_verify?(tokens)

    nil
  end

  # `git commit ... -n` (short alias for --no-verify), anywhere after `commit`.
  def commit_short_no_verify?(tokens)
    after = tokens_after_subcommand(tokens, "commit")
    after&.any? { |token| token.match?(SHORT_N_FLAG) } || false
  end

  # Tokens following `<sub>` when the command is `git <sub>`; nil otherwise.
  def tokens_after_subcommand(tokens, sub)
    git = tokens.index("git")
    return nil unless git

    sub_index = tokens[git..].index(sub)
    return nil unless sub_index

    tokens[(git + sub_index + 1)..]
  end

  def deny(reason)
    $stdout.puts JSON.generate(
      "hookSpecificOutput" => {
        "hookEventName" => "PreToolUse",
        "permissionDecision" => "deny",
        "permissionDecisionReason" => reason
      }
    )
  end
end

ProcessLock.call($stdin.read) if $PROGRAM_NAME == __FILE__
