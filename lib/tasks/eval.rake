# Accuracy eval for the commodity-code classifier against labelled UK Advance
# Tariff Rulings (10-digit ground truth).
#
#   bin/rails "eval:rulings"
#
# ENV:
#   EVAL_FILE          input rulings JSON (default test/eval/rulings_eval_set.json)
#   EVAL_OUT           output JSON (default test/eval/results/<pipeline>-<chooser>-<timestamp>.json)
#   EVAL_LIMIT         only run the first N rulings
#   TARIFFIK_PIPELINE  "legacy" to run LegacyCommoditySuggester instead of the pipeline
#   TARIFFIK_CHOOSER   "jev" to use JevChooser (if defined) instead of ClaudeChooser
#
# Runs SEQUENTIALLY on purpose: the tariff API rate-limits parallel callers and
# silently returns empty results, which would corrupt the scores.
namespace :eval do
  desc "Score the commodity classifier against labelled tariff rulings"
  task rulings: :environment do
    require "json"

    pipeline = ENV["TARIFFIK_PIPELINE"] == "legacy" ? "legacy" : "pipeline"
    chooser = ENV["TARIFFIK_CHOOSER"].presence || "claude"

    eval_file = ENV["EVAL_FILE"].presence || Rails.root.join("test/eval/rulings_eval_set.json").to_s
    items = JSON.parse(File.read(eval_file), symbolize_names: true)
    items = items.first(ENV["EVAL_LIMIT"].to_i) if ENV["EVAL_LIMIT"].present?

    timestamp = Time.now.utc.strftime("%Y%m%d-%H%M%S")
    default_out = Rails.root.join("test/eval/results/#{pipeline}-#{chooser}-#{timestamp}.json")
    out_path = ENV["EVAL_OUT"].presence || default_out.to_s
    FileUtils.mkdir_p(File.dirname(out_path))

    suggester = LlmCommoditySuggester.new
    results = []

    items.each_with_index do |item, i|
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      suggestion, usage = Classification::TokenMeter.measure { suggester.suggest(item[:description]) }
      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round

      truth = digits(item[:code])
      predicted = digits(suggestion&.dig(:commodity_code))
      depth = match_depth(truth, predicted)

      results << {
        ruling: item[:ruling],
        truth: truth,
        truth_desc: item[:description].to_s[0, 140],
        predicted: predicted,
        confidence: suggestion&.dig(:confidence),
        validated: suggestion&.dig(:validated),
        reasoning: suggestion&.dig(:reasoning).to_s[0, 300],
        depth: depth,
        ms: ms,
        tokens: usage,
        steps: suggestion&.dig(:steps) || []
      }

      warn "#{i + 1}/#{items.size} truth=#{truth} pred=#{predicted} depth=#{depth} " \
           "conf=#{suggestion&.dig(:confidence)} calls=#{usage[:calls]} (#{ms}ms)"
    end

    File.write(out_path, JSON.pretty_generate(results))
    print_summary(results, pipeline: pipeline, chooser: chooser, out_path: out_path)
  end
end

def digits(value)
  value.to_s.gsub(/\D/, "")
end

def match_depth(truth, predicted)
  a = digits(truth)
  b = digits(predicted)
  [ 10, 8, 6, 4, 2 ].find { |n| a.size >= n && b.size >= n && a[0, n] == b[0, n] } || 0
end

def print_summary(results, pipeline:, chooser:, out_path:)
  n = results.size
  total = n.to_f

  puts "\n=== eval:rulings — #{pipeline}/#{chooser} — #{n} rulings ==="

  puts "\nAccuracy by depth:"
  [ 2, 4, 6, 8, 10 ].each do |d|
    correct = results.count { |r| r[:depth] >= d }
    puts format("  %2d-digit: %3d/%-3d (%d%%)", d, correct, n, pct(correct, total))
  end

  no_pred = results.count { |r| r[:predicted].to_s.empty? }
  unvalidated = results.count { |r| r[:validated] == false }
  puts "\n  no suggestion:     #{no_pred}"
  puts "  unvalidated codes: #{unvalidated}"

  right = results.select { |r| r[:depth] >= 10 }.filter_map { |r| r[:confidence]&.to_f }
  wrong = results.select { |r| r[:depth] < 10 }.filter_map { |r| r[:confidence]&.to_f }
  puts "  mean confidence when right (10-digit): #{mean(right)}; when wrong: #{mean(wrong)}"

  latencies = results.map { |r| r[:ms] }.sort
  puts "  median latency: #{latencies[n / 2]}ms" unless latencies.empty?

  in_tok = results.sum { |r| r.dig(:tokens, :input).to_i }
  out_tok = results.sum { |r| r.dig(:tokens, :output).to_i }
  calls = results.sum { |r| r.dig(:tokens, :calls).to_i }
  if calls.positive?
    puts "  Claude tokens: in=#{in_tok} out=#{out_tok}; calls=#{calls} (#{(calls / total).round(1)}/lookup)"
  end

  puts "\nCalibration (confidence bucket → n, 10-digit acc, 8-digit acc):"
  buckets = [ [ "0.0-0.5", 0.0, 0.5 ], [ "0.5-0.7", 0.5, 0.7 ], [ "0.7-0.9", 0.7, 0.9 ], [ "0.9-1.0", 0.9, 1.01 ] ]
  buckets.each do |label, low, high|
    in_bucket = results.select do |r|
      c = r[:confidence].to_f
      c >= low && c < high
    end
    next puts format("  %-8s: %3d", label, 0) if in_bucket.empty?

    d10 = in_bucket.count { |r| r[:depth] >= 10 }
    d8 = in_bucket.count { |r| r[:depth] >= 8 }
    puts format("  %-8s: %3d   10-digit %3d%%   8-digit %3d%%",
                label, in_bucket.size, pct(d10, in_bucket.size), pct(d8, in_bucket.size))
  end

  a10 = pct(results.count { |r| r[:depth] >= 10 }, total)
  a8 = pct(results.count { |r| r[:depth] >= 8 }, total)
  puts "\nSummary: #{pipeline}/#{chooser} — 10-digit #{a10}%, 8-digit #{a8}%, #{no_pred} misses, wrote #{out_path}"
end

def pct(count, total)
  return 0 if total.to_f.zero?

  (100 * count / total.to_f).round
end

def mean(values)
  return "n/a" if values.empty?

  (values.sum / values.size).round(2)
end
