# Tool definitions advertised over the Model Context Protocol.
#
# Descriptions are written for the calling model, not for humans: they say when
# to reach for a tool as much as what it does, because that is what an agent
# uses to choose between them.
module Mcp
  class ToolCatalog
    SERVER_NAME = "tariffik"
    SERVER_VERSION = "1.0.0"

    # Version we speak. Clients may ask for an older one; anything in
    # SUPPORTED_PROTOCOL_VERSIONS is echoed back rather than refused.
    PROTOCOL_VERSION = "2025-06-18"
    SUPPORTED_PROTOCOL_VERSIONS = %w[2025-06-18 2025-03-26 2024-11-05].freeze

    INSTRUCTIONS = <<~TEXT.freeze
      Tariffik suggests UK/EU commodity (HS) codes for physical goods.

      Typical flow when working through order or shipping emails: pull the
      product link out of each email, call lookup_from_url on it, and fall back
      to lookup_from_description when a link is missing, dead, or behind a
      login. Lookups are saved to the Tariffik account by default so they show
      up in the dashboard and CSV export for a customs declaration.

      Codes come back as 10-digit UK commodity codes and are validated against
      the UK Trade Tariff API where possible. A suggestion with validated=false
      was not found in the tariff and should be treated as a starting point.
    TEXT

    TOOLS = [
      {
        name: "lookup_from_url",
        title: "Look up a commodity code from a product URL",
        description: <<~TEXT.strip,
          Suggest a UK/EU commodity (HS) code for the product at a URL. Scrapes the
          product page, then picks and validates a code against the UK Trade Tariff.

          This is the tool to use for a product link found in an order confirmation
          or shipping email. Takes several seconds because it fetches the page.
          Returns the code, a confidence score, the reasoning, the duty rate, and
          what was scraped from the page so you can sanity-check the match.
        TEXT
        inputSchema: {
          type: "object",
          properties: {
            url: {
              type: "string",
              description: "Direct link to a single product page. Not a basket, order-status, or category page."
            },
            save: {
              type: "boolean",
              default: true,
              description: "Save the result to the Tariffik account so it appears in the dashboard and CSV export."
            }
          },
          required: [ "url" ],
          additionalProperties: false
        }
      },
      {
        name: "lookup_from_description",
        title: "Look up a commodity code from a description",
        description: <<~TEXT.strip,
          Suggest a UK/EU commodity (HS) code from a written product description.

          Use when there is no usable product link, for example when the email only
          names the item, or when lookup_from_url failed. Include whatever is known:
          what the item is, brand, material or composition, and intended use, since
          material drives the code for clothing, textiles, and many other goods.
        TEXT
        inputSchema: {
          type: "object",
          properties: {
            description: {
              type: "string",
              description: "e.g. \"Men's short-sleeve t-shirt, 100% cotton, knitted, brand Uniqlo\"."
            },
            save: {
              type: "boolean",
              default: true,
              description: "Save the result to the Tariffik account so it appears in the dashboard and CSV export."
            }
          },
          required: [ "description" ],
          additionalProperties: false
        }
      },
      {
        name: "search_codes",
        title: "Search the UK Trade Tariff",
        description: <<~TEXT.strip,
          Free-text search of the UK Trade Tariff, returning candidate commodity
          codes ranked by relevance. No AI judgement is applied.

          Use to explore what codes exist for a category, or to check alternatives
          when a suggestion looks wrong. For an actual answer on a specific product,
          prefer lookup_from_url or lookup_from_description.
        TEXT
        inputSchema: {
          type: "object",
          properties: {
            query: { type: "string", description: "Search terms, e.g. \"cotton t-shirt\" or \"lithium battery\"." },
            limit: { type: "integer", default: 10, minimum: 1, maximum: 50, description: "Maximum results to return." }
          },
          required: [ "query" ],
          additionalProperties: false
        }
      },
      {
        name: "get_code",
        title: "Get details for a commodity code",
        description: <<~TEXT.strip,
          Fetch the official description, duty rate, and any notes for a specific
          commodity code from the UK Trade Tariff.

          Use to verify a code before putting it on a declaration, or to explain
          what a code someone else supplied actually covers.
        TEXT
        inputSchema: {
          type: "object",
          properties: {
            code: {
              type: "string",
              description: "Commodity code, 6 to 10 digits. Spaces, dots, and dashes are ignored, so \"6109 10 0010\" is fine."
            }
          },
          required: [ "code" ],
          additionalProperties: false
        }
      },
      {
        name: "list_recent_lookups",
        title: "List recent saved lookups",
        description: <<~TEXT.strip,
          List commodity code lookups already saved to this Tariffik account, newest
          first.

          Use to avoid looking the same product up twice when working through a
          batch of emails, or to gather the codes for a declaration covering a
          period. Shows whether each code is still an AI suggestion or has been
          confirmed by the account owner.
        TEXT
        inputSchema: {
          type: "object",
          properties: {
            limit: { type: "integer", default: 20, minimum: 1, maximum: 100, description: "Maximum lookups to return." },
            since: { type: "string", description: "Only lookups created on or after this date or timestamp (ISO 8601, e.g. \"2026-09-01\")." }
          },
          additionalProperties: false
        }
      }
    ].freeze

    TOOL_NAMES = TOOLS.map { |tool| tool[:name] }.freeze

    def self.tools
      TOOLS
    end

    def self.tool?(name)
      TOOL_NAMES.include?(name)
    end

    def self.negotiate_protocol_version(requested)
      return PROTOCOL_VERSION if requested.blank?

      SUPPORTED_PROTOCOL_VERSIONS.include?(requested) ? requested : PROTOCOL_VERSION
    end

    def self.server_info
      { name: SERVER_NAME, version: SERVER_VERSION }
    end
  end
end
