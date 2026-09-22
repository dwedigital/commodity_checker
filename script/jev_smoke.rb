# frozen_string_literal: true

# Live smoke test for the TypeSafe AI "Jev" integration.
#
#   bin/rails runner script/jev_smoke.rb
#
# Makes real calls to https://api.typesafe.ai using TYPESAFE_API_KEY from .env.
# Prints the answers, per-call latency and input tokens. Never prints the key.

require "benchmark"

BAR = ("=" * 78)

def section(title)
  puts
  puts BAR
  puts title
  puts BAR
end

# Report a raw JevClient response: answers, input tokens, latency.
def report(result, seconds)
  if result.nil?
    puts "  -> nil (request failed; see the [jev] warning in the log)"
    return
  end
  puts "  model:        #{result['model']}"
  result["answers"].each do |qid, answer|
    puts "  answer[#{qid}]: #{answer.inspect}"
  end
  puts "  input_tokens: #{result.dig('usage', 'input_tokens')}"
  puts "  latency:      #{format('%.2f', seconds)}s"
end

# Report a Classification::JevChooser#choose result (the walker's contract).
def report_choice(result, seconds)
  if result.nil?
    puts "  -> nil (chooser returned nil; the walker would fall back)"
    return
  end
  top = Array(result[:probabilities]).max_by { |_key, prob| prob }
  puts "  key:          #{result[:key]}"
  puts "  confidence:   #{result[:confidence]}"
  puts "  chooser:      #{result[:chooser]}"
  puts "  reasoning:    #{result[:reasoning]}"
  puts "  top prob:     #{top.inspect}"
  puts "  latency:      #{format('%.2f', seconds)}s"
end

# A stand-in for a real fallback chooser (ClaudeChooser), so numeric delegation
# can be demonstrated without a live Claude call.
class StubFallback
  def choose(question:, options:, context:)
    first = options.first
    { key: first[:key], confidence: 0.8, probabilities: { first[:key] => 0.8 },
      reasoning: "stub fallback (a real setup would delegate to ClaudeChooser)", chooser: "claude" }
  end
end

client = JevClient.new

unless client.configured?
  puts "TYPESAFE_API_KEY is not configured. Set it in .env and retry."
  exit 1
end

# ---------------------------------------------------------------------------
# (a) Heading 6109: a choice + a noul, straight through JevClient.
# ---------------------------------------------------------------------------
section "(a) JevClient.evaluate  ->  heading 6109 leaf choice + knitted noul"

state_a = {
  product: "Football tops for a junior team. It is knitted. It is made from polyester.",
  classified_so_far: "Section XI > Chapter 61 Articles of apparel, knitted or crocheted > " \
                     "Heading 6109 T-shirts, singlets and other vests, knitted or crocheted"
}
questions_a = {
  "leaf" => JevClient.choice(
    instructions: "Which commodity line under heading 6109 correctly classifies `product`? " \
                  "Choose by the textile material of the garment.",
    criteria: {
      "6109100010" => "Of cotton > T-shirts",
      "6109100090" => "Of cotton > Other (singlets and other vests)",
      "6109902000" => "Of other textile materials > Of wool or fine animal hair or man-made fibres",
      "6109909000" => "Of other textile materials > Of other textile materials"
    }
  ),
  "knitted" => JevClient.noul(
    instructions: "Is `product` knitted or crocheted (as opposed to woven)?"
  )
}

result_a = nil
seconds_a = Benchmark.realtime { result_a = client.evaluate(state: state_a, questions: questions_a) }
report(result_a, seconds_a)

# ---------------------------------------------------------------------------
# (b) Heading-level choice across ~20 Chapter 61/62 headings.
# ---------------------------------------------------------------------------
section "(b) Heading-level choice across 20 headings (JevClient + JevChooser)"

heading_options = [
  { key: "6101", label: "Men's or boys' overcoats, anoraks and similar articles, knitted or crocheted" },
  { key: "6102", label: "Women's or girls' overcoats, anoraks and similar articles, knitted or crocheted" },
  { key: "6103", label: "Men's or boys' suits, jackets, trousers and shorts, knitted or crocheted" },
  { key: "6104", label: "Women's or girls' suits, dresses, skirts, trousers and shorts, knitted or crocheted" },
  { key: "6105", label: "Men's or boys' shirts, knitted or crocheted" },
  { key: "6106", label: "Women's or girls' blouses and shirts, knitted or crocheted" },
  { key: "6107", label: "Men's or boys' underpants, briefs, nightshirts and pyjamas, knitted or crocheted" },
  { key: "6108", label: "Women's or girls' slips, briefs, nightdresses and pyjamas, knitted or crocheted" },
  { key: "6109", label: "T-shirts, singlets and other vests, knitted or crocheted" },
  { key: "6110", label: "Jerseys, pullovers, cardigans, waistcoats and similar articles, knitted or crocheted" },
  { key: "6111", label: "Babies' garments and clothing accessories, knitted or crocheted" },
  { key: "6112", label: "Track suits, ski suits and swimwear, knitted or crocheted" },
  { key: "6113", label: "Garments made up of impregnated, coated or laminated knitted fabric" },
  { key: "6114", label: "Other garments, knitted or crocheted" },
  { key: "6115", label: "Tights, stockings, socks and other hosiery, knitted or crocheted" },
  { key: "6116", label: "Gloves, mittens and mitts, knitted or crocheted" },
  { key: "6117", label: "Other made-up clothing accessories, knitted or crocheted; parts of garments" },
  { key: "6201", label: "Men's or boys' overcoats and anoraks (not knitted or crocheted)" },
  { key: "6205", label: "Men's or boys' shirts (not knitted or crocheted)" },
  { key: "6206", label: "Women's or girls' blouses and shirts (not knitted or crocheted)" }
]

product_b = "A plain short-sleeved cotton T-shirt for adults, knitted single jersey, crew neck, no print."
question_b = "Which heading best classifies `product`? Choose by garment type and construction."

puts "  numeric_level? #{Classification::JevChooser.numeric_level?(heading_options)}"

# The exact request the chooser sends (surfaces the token count).
criteria_b = heading_options.each_with_object({}) { |o, h| h[o[:key]] = o[:label] }
result_b = nil
seconds_b = Benchmark.realtime do
  result_b = client.evaluate(
    state: { product: product_b, classified_so_far: "Section XI > Chapter 61 Articles of apparel, knitted or crocheted" },
    questions: { "heading" => JevClient.choice(instructions: question_b, criteria: criteria_b) }
  )
end
report(result_b, seconds_b)

# The same decision through the chooser, mapped onto the walker's contract.
puts
puts "  via Classification::JevChooser#choose:"
chooser_b = Classification::JevChooser.new(client: client)
context_b = {
  product: product_b,
  path: [ "Section XI Textiles and textile articles", "Chapter 61 Articles of apparel, knitted or crocheted" ],
  level: :heading
}
choice_b = nil
seconds_b2 = Benchmark.realtime { choice_b = chooser_b.choose(question: question_b, options: heading_options, context: context_b) }
report_choice(choice_b, seconds_b2)

# ---------------------------------------------------------------------------
# (c) Numeric-threshold level: demonstrate numeric_level? routing.
# ---------------------------------------------------------------------------
section "(c) Numeric-threshold level  ->  numeric_level? routing"

numeric_options = [
  { key: "5208310000", label: "Plain weave, weighing not more than 100 g/m2" },
  { key: "5208320000", label: "Plain weave, weighing more than 100 g/m2 but not more than 200 g/m2" },
  { key: "5209310000", label: "Plain weave, weighing more than 200 g/m2" },
  { key: "5211310000", label: "Other woven fabrics, plain weave, weighing more than 200 g/m2" }
]

context_c = {
  product: "Woven cotton shirting fabric, plain weave, unbleached, approximately 180 g/m2.",
  path: [ "Section XI", "Chapter 52 Cotton", "Woven fabrics of cotton" ],
  level: :node
}
question_c = "Which weight band correctly classifies `product`?"

puts "  numeric_level? #{Classification::JevChooser.numeric_level?(numeric_options)}  (Jev is weak on numeric comparisons)"

# What a no-fallback chooser sends to Jev (surfaces the token count). Jev may
# still answer, but the result is flagged unreliable.
criteria_c = numeric_options.each_with_object({}) { |o, h| h[o[:key]] = o[:label] }
result_c = nil
seconds_c = Benchmark.realtime do
  result_c = client.evaluate(
    state: { product: context_c[:product], classified_so_far: context_c[:path].join(" > ") },
    questions: { "band" => JevClient.choice(instructions: question_c, criteria: criteria_c) }
  )
end
report(result_c, seconds_c)

puts
puts "  routing with a fallback chooser (delegates, no Jev call):"
routed = Classification::JevChooser.new(client: client, fallback: StubFallback.new)
                                   .choose(question: question_c, options: numeric_options, context: context_c)
report_choice(routed, 0.0)

puts
puts "  routing without a fallback (asks Jev, flags the caveat):"
no_fallback = nil
seconds_nf = Benchmark.realtime do
  no_fallback = Classification::JevChooser.new(client: client)
                                          .choose(question: question_c, options: numeric_options, context: context_c)
end
report_choice(no_fallback, seconds_nf)

puts
puts BAR
puts "done"
