# frozen_string_literal: true

require "anthropic"

module Services::Budgets
  # One batched Anthropic call resolving budget names that exact/fuzzy
  # tiers could not. Never raises to callers: any API or parse failure
  # returns {} (MappingSuggester treats missing keys as unresolved and the
  # next sync retries). LLM verdicts are suggestion-grade only — the
  # suggester stores them with confidence 0.75 and never auto-applies.
  class MappingLlmResolver
    MODEL = "claude-haiku-4-5-20251001"
    MAX_TOKENS = 2000
    ALLOCATION = "ALLOCATION"
    UNKNOWN = "UNKNOWN"

    def initialize(client: nil)
      @client = client
    end

    def resolve(names:, categories:, user:)
      return {} if names.empty?

      text = request_text(names, categories)
      parse(text, categories)
    rescue StandardError => e
      Rails.logger.error("[MappingLlmResolver] LLM call failed: #{e.class} #{e.message}")
      {}
    end

    private

    def request_text(names, categories)
      response = client.messages.create(
        model: MODEL,
        max_tokens: MAX_TOKENS,
        temperature: 0.0,
        messages: [ { role: :user, content: prompt(names, categories) } ]
      )
      response.content.find { |block| block.type == "text" }&.text.to_s
    end

    def prompt(names, categories)
      <<~PROMPT
        You map personal budget line names (Spanish/English mix, Costa Rica) to expense categories.

        Budget names:
        #{names.map { |n| "- #{n}" }.join("\n")}

        Allowed categories (answer with the EXACT name):
        #{categories.map(&:name).join(", ")}

        For each budget name answer with exactly one of:
        - an EXACT category name from the list above,
        - "#{ALLOCATION}" if the name is a person, family transfer, savings/investment allocation, or insurance — money set aside, not a spendable expense category,
        - "#{UNKNOWN}" if genuinely unsure.

        Respond with ONLY a JSON array, no prose:
        [{"name":"<budget name>","answer":"<category name|#{ALLOCATION}|#{UNKNOWN}>"}]
      PROMPT
    end

    def parse(text, categories)
      json = text[/\[.*\]/m]
      raise ArgumentError, "no JSON array in response" if json.nil?

      by_name = categories.index_by { |c| c.name }
      JSON.parse(json).each_with_object({}) do |row, acc|
        name = row["name"].to_s
        answer = row["answer"].to_s
        next if answer == UNKNOWN || name.blank?

        if answer == ALLOCATION
          acc[name] = { category: nil, kind: :allocation }
        elsif (category = by_name[answer])
          acc[name] = { category: category, kind: :category }
        end
      end
    rescue JSON::ParserError, ArgumentError => e
      Rails.logger.error("[MappingLlmResolver] malformed LLM response: #{e.message}")
      {}
    end

    def client
      @client ||= Anthropic::Client.new(
        api_key: Rails.application.credentials.dig(:anthropic, :api_key).presence ||
                 ENV["ANTHROPIC_API_KEY"],
        timeout: 30
      )
    end
  end
end
