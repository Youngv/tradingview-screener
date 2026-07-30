# frozen_string_literal: true

module TradingviewScreener
  # Arel-like column node used inside where().
  #
  #   Screener[:close].gt(Screener[:SMA20])
  #   Screener[:volume].gte(1_000_000)
  #   Screener[:close].between(10, 300)
  class Predicate
    attr_reader :left, :operation, :right

    def initialize(left, operation, right = nil)
      @left = left.to_s
      @operation = operation.to_s
      @right = unwrap(right)
    end

    def to_h
      { "left" => left, "operation" => operation, "right" => right }
    end

    def inspect
      "#<#{self.class} #{left} #{operation} #{right.inspect}>"
    end

    private

    def unwrap(value)
      case value
      when Predicate then value.left
      when Field then value.name
      when Symbol then value.to_s
      else value
      end
    end
  end

  class Field
    attr_reader :name

    def initialize(name)
      @name = name.to_s
    end

    def gt(other) = Predicate.new(name, "greater", other)
    def gte(other) = Predicate.new(name, "egreater", other)
    def lt(other) = Predicate.new(name, "less", other)
    def lte(other) = Predicate.new(name, "eless", other)
    def eq(other) = Predicate.new(name, "equal", other)
    def not_eq(other) = Predicate.new(name, "nequal", other)
    def between(min, max) = Predicate.new(name, "in_range", [unwrap(min), unwrap(max)])
    def not_between(min, max) = Predicate.new(name, "not_in_range", [unwrap(min), unwrap(max)])
    def in(values) = Predicate.new(name, "in_range", Array(values))
    def not_in(values) = Predicate.new(name, "not_in_range", Array(values))
    def has(values) = Predicate.new(name, "has", values)
    def has_none_of(values) = Predicate.new(name, "has_none_of", values)
    def matches(value) = Predicate.new(name, "match", value)
    def does_not_match(value) = Predicate.new(name, "nmatch", value)
    def blank = Predicate.new(name, "empty", nil)
    def present = Predicate.new(name, "nempty", nil)
    def crosses(other) = Predicate.new(name, "crosses", other)
    def crosses_above(other) = Predicate.new(name, "crosses_above", other)
    def crosses_below(other) = Predicate.new(name, "crosses_below", other)

    def >(other) = gt(other)
    def >=(other) = gte(other)
    def <(other) = lt(other)
    def <=(other) = lte(other)
    def ==(other) = eq(other)
    def !=(other) = not_eq(other)

    def inspect
      "#<#{self.class} #{name}>"
    end

    private

    def unwrap(value)
      value.is_a?(Field) ? value.name : value
    end
  end

  # Operator wrappers for hash-style where:
  #   where(close: gt(:SMA20), volume: gte(1_000_000), price: 10..300)
  module Predicates
    module_function

    def gt(value) = Op.new("greater", value)
    def gte(value) = Op.new("egreater", value)
    def lt(value) = Op.new("less", value)
    def lte(value) = Op.new("eless", value)
    def not_eq(value) = Op.new("nequal", value)
    def has(value) = Op.new("has", value)
    def has_none_of(value) = Op.new("has_none_of", value)

    class Op
      attr_reader :operation, :value

      def initialize(operation, value)
        @operation = operation
        @value = value.is_a?(Field) || value.is_a?(Symbol) ? value.to_s.sub(/\A:/, "") : value
        @value = value.name if value.is_a?(Field)
        @value = value.to_s if value.is_a?(Symbol)
      end
    end
  end
end
