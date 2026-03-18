# frozen_string_literal: true

require "dry-types"
require "dry-struct"

module Types
  include Dry.Types()
end

class SearchSetting < Dry::Struct
  transform_keys(&:to_sym)
  schema schema.strict

  attribute :name, Types::String
  attribute :bio, Types::String
  attribute :avatar, Types::String
  attribute :query, Types::Array.of(Types::String)
  attribute? :period_days, Types::Coercible::Integer.default(183)
end

SearchSettings = Types::Hash.map(Types::String, SearchSetting)

def parse_input(data) = SearchSettings[data]
