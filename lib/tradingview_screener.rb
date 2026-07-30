# frozen_string_literal: true

require_relative "tradingview_screener/version"
require_relative "tradingview_screener/predicate"
require_relative "tradingview_screener/client"
require_relative "tradingview_screener/relation"
require_relative "tradingview_screener/screen_data"
require_relative "tradingview_screener/base"

module TradingviewScreener
  module_function

  # Field helper: TradingviewScreener[:close]
  def [](name)
    Field.new(name)
  end

  # Include predicate helpers into Relation instances for scope blocks.
  module QueryMethods
    def gt(value) = Predicates.gt(value)
    def gte(value) = Predicates.gte(value)
    def lt(value) = Predicates.lt(value)
    def lte(value) = Predicates.lte(value)
    def not_eq(value) = Predicates.not_eq(value)
    def has(value) = Predicates.has(value)
    def has_none_of(value) = Predicates.has_none_of(value)
  end

  Relation.include(QueryMethods)
  Base.extend(QueryMethods)
end
