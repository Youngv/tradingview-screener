# frozen_string_literal: true

require "json"

module TradingviewScreener
  # ActiveRecord-style immutable relation for TradingView scanner.
  #
  #   Stock.where(is_primary: true)
  #        .where(close: 10..300)
  #        .where(close: gt(:SMA20))
  #        .order(premarket_volume: :desc)
  #        .limit(100)
  #        .load
  class Relation
    include Enumerable

    SCAN_URL = "https://scanner.tradingview.com/%<market>s/scan"
    DEFAULT_RANGE = [0, 50].freeze

    STOCK_TYPE_FILTER2 = {
      "operator" => "and",
      "operands" => [
        {
          "operation" => {
            "operator" => "or",
            "operands" => [
              {
                "operation" => {
                  "operator" => "and",
                  "operands" => [
                    { "expression" => { "left" => "type", "operation" => "equal", "right" => "stock" } },
                    { "expression" => { "left" => "typespecs", "operation" => "has", "right" => ["common"] } }
                  ]
                }
              },
              {
                "operation" => {
                  "operator" => "and",
                  "operands" => [
                    { "expression" => { "left" => "type", "operation" => "equal", "right" => "stock" } },
                    { "expression" => { "left" => "typespecs", "operation" => "has", "right" => ["preferred"] } }
                  ]
                }
              },
              {
                "operation" => {
                  "operator" => "and",
                  "operands" => [
                    { "expression" => { "left" => "type", "operation" => "equal", "right" => "dr" } }
                  ]
                }
              },
              {
                "operation" => {
                  "operator" => "and",
                  "operands" => [
                    { "expression" => { "left" => "type", "operation" => "equal", "right" => "fund" } },
                    { "expression" => { "left" => "typespecs", "operation" => "has_none_of", "right" => %w[etf mutual closedend] } }
                  ]
                }
              }
            ]
          }
        },
        { "expression" => { "left" => "typespecs", "operation" => "has_none_of", "right" => ["pre-ipo"] } }
      ]
    }.freeze

    attr_reader :klass

    def initialize(klass = nil, values: nil)
      @klass = klass
      @values = values || default_values(klass)
      @records = nil
      @loaded = false
    end

    def self.from_payload(klass, payload)
      payload = payload.to_h.transform_keys(&:to_s)
      filters = Array(payload["filter"]).map { |item| item.to_h.transform_keys(&:to_s) }
      sort = payload["sort"].to_h.transform_keys(&:to_s)
      range = Array(payload["range"])
      offset = range[0] ? Integer(range[0]) : 0
      limit =
        if range[1]
          Integer(range[1]) - offset
        end

      markets = Array(payload["markets"]).map(&:to_s)
      markets = ["america"] if markets.empty?
      overrides = {
        "where_values" => filters,
        "markets" => markets,
        "tickers" => Array(payload.dig("symbols", "tickers")),
        "filter2" => payload["filter2"] || deep_dup_static(STOCK_TYPE_FILTER2),
        "none_value" => false,
        "offset_value" => offset
      }
      overrides["select_values"] = Array(payload["columns"]).map(&:to_s) if Array(payload["columns"]).any?
      if sort["sortBy"] && !sort["sortBy"].to_s.empty?
        overrides["order_values"] = [{
          "sortBy" => sort["sortBy"].to_s,
          "sortOrder" => (sort["sortOrder"] || "desc").to_s
        }]
      end
      overrides["limit_value"] = limit if limit && limit.positive?

      base = new(klass)
      merged = base.send(:deep_dup, base.values)
      overrides.each { |key, value| merged[key.to_sym] = value }
      new(klass, values: merged)
    end

    def self.deep_dup_static(value)
      case value
      when Hash then value.each_with_object({}) { |(k, v), memo| memo[k] = deep_dup_static(v) }
      when Array then value.map { |item| deep_dup_static(item) }
      when String then value.dup
      else value
      end
    end

    def select(*columns)
      spawn(select_values: columns.flatten.map { |c| field_name(c) })
    end

    # AR-like where:
    #   where(is_primary: true)
    #   where(close: 10..300)
    #   where(type: %w[stock fund])
    #   where(close: gt(:SMA20))
    #   where(Screener[:volume].gt(1_000_000))
    #   where(Screener[:close].gt(Screener[:SMA20]), is_primary: true)
    def where(*predicates, **conditions)
      filters = predicates.map { |item| normalize_predicate(item) }
      conditions.each { |key, value| filters.concat(build_condition(key, value)) }
      spawn(where_values: where_values + filters)
    end

    def rewhere(**conditions)
      keys = conditions.keys.map { |key| field_name(key) }
      kept = where_values.reject { |item| keys.include?(item["left"]) }
      replacement = conditions.flat_map { |key, value| build_condition(key, value) }
      spawn(where_values: kept + replacement)
    end

    def order(*args, **kwargs)
      sorts = []
      args.each do |arg|
        case arg
        when Hash
          arg.each { |key, dir| sorts << sort_entry(key, dir) }
        when String, Symbol
          sorts << sort_entry(arg, :asc)
        else
          raise ArgumentError, "unsupported order value: #{arg.inspect}"
        end
      end
      kwargs.each { |key, dir| sorts << sort_entry(key, dir) }
      return self if sorts.empty?

      spawn(order_values: sorts)
    end

    def limit(value)
      spawn(limit_value: Integer(value))
    end

    def offset(value)
      spawn(offset_value: Integer(value))
    end

    def market(*markets)
      list = markets.flatten.compact.map(&:to_s)
      spawn(markets: list)
    end

    def tickers(*tickers)
      spawn(tickers: tickers.flatten.map(&:to_s), markets: [])
    end

    def except(*keys)
      next_values = deep_dup(@values)
      keys.map(&:to_sym).each do |key|
        case key
        when :where then next_values[:where_values] = []
        when :order then next_values[:order_values] = []
        when :select then next_values[:select_values] = default_select
        when :limit then next_values[:limit_value] = DEFAULT_RANGE[1]
        when :offset then next_values[:offset_value] = 0
        else
          raise ArgumentError, "unknown except key: #{key}"
        end
      end
      self.class.new(klass, values: next_values)
    end

    def merge(other)
      raise ArgumentError, "merge expects Relation" unless other.is_a?(Relation)

      spawn(
        select_values: other.values[:select_values] || select_values,
        where_values: where_values + other.where_values,
        order_values: (other.order_values.empty? ? order_values : other.order_values),
        limit_value: other.values[:limit_value] || limit_value,
        offset_value: other.values[:offset_value] || offset_value,
        markets: other.values[:markets] || markets,
        tickers: other.values[:tickers] || tickers_value,
        filter2: other.values[:filter2] || filter2
      )
    end

    def unscope(*args)
      except(*args)
    end

    def none
      spawn(none_value: true)
    end

    def load(client: nil, cookies: nil, headers: nil, timeout: 20, label_product: "screener-stock", proxy: nil)
      return self if loaded?

      if none_value?
        @records = []
        @total_count = 0
        @raw = { "totalCount" => 0, "data" => [] }
      else
        raw = execute(
          client: client,
          cookies: cookies,
          headers: headers,
          timeout: timeout,
          label_product: label_product,
          proxy: proxy
        )
        @raw = raw
        @total_count = parse_total_count(raw)
        @records = map_rows(raw)
      end
      @loaded = true
      self
    end

    def reload(**opts)
      reset
      load(**opts)
    end

    def reset
      @loaded = false
      @records = nil
      @total_count = nil
      @raw = nil
      self
    end

    def loaded?
      @loaded
    end

    def to_a(**opts)
      load(**opts) unless loaded?
      records.dup
    end

    def records
      load unless loaded?
      @records
    end

    def each(...)
      records.each(...)
    end

    def size
      records.size
    end
    alias length size

    def empty?
      size.zero?
    end

    def exists?(**opts)
      if loaded?
        !records.empty?
      else
        limit(1).load(**opts).size.positive?
      end
    end

    def count(**opts)
      if loaded?
        total_count
      else
        load(**opts).total_count
      end
    end

    def total_count
      load unless loaded?
      @total_count
    end

    def first(n = nil, **opts)
      rel = loaded? ? self : limit(n || 1).load(**opts)
      n ? rel.records.first(n) : rel.records.first
    end

    def last(n = nil, **opts)
      rows = to_a(**opts)
      n ? rows.last(n) : rows.last
    end

    def pluck(*columns, **opts)
      cols = columns.flatten.map { |c| field_name(c) }
      rel = select_values == cols ? self : select(*cols)
      rel.to_a(**opts).map do |row|
        if cols.size == 1
          row[cols.first]
        else
          cols.map { |col| row[col] }
        end
      end
    end

    def pick(*columns, **opts)
      limit(1).pluck(*columns, **opts).first
    end

    def ids(**opts)
      load(**opts) unless loaded?
      records.map { |row| row["ticker"] }
    end

    def tickers_list(**opts)
      ids(**opts)
    end

    def symbols(**opts)
      ids(**opts).map do |ticker|
        exchange, symbol = ticker.to_s.split(":", 2)
        {
          "exchange" => exchange,
          "symbol" => symbol,
          "full_symbol" => ticker
        }
      end
    end

    def raw
      load unless loaded?
      @raw
    end

    def to_sql
      # scanner has no SQL; show the request payload for debugging (AR-ish inspect helper)
      JSON.pretty_generate(to_query)
    end

    def to_query
      {
        "markets" => markets,
        "symbols" => symbols_payload,
        "options" => { "lang" => "en" },
        "columns" => select_values,
        "filter" => where_values,
        "filter2" => filter2,
        "sort" => order_payload,
        "range" => [offset_value, offset_value + limit_value],
        "ignore_unknown_fields" => false
      }.compact
    end
    alias to_h to_query

    def scanner_url
      market = markets.size == 1 ? markets.first : "global"
      market = "global" if market.nil? || market.empty?
      format(SCAN_URL, market: market)
    end

    def selected_columns
      select_values
    end

    def inspect
      if loaded?
        entries = records.first(3).map { |row| row["ticker"] || row["name"] }
        entries << "..." if records.size > 3
        "#<#{self.class.name} [#{entries.join(', ')}] size=#{records.size} total=#{total_count}>"
      else
        "#<#{self.class.name} market=#{markets.inspect} where=#{where_values.size} order=#{order_values.inspect} limit=#{limit_value}>"
      end
    end

    def ==(other)
      other.is_a?(self.class) && other.to_query == to_query
    end

    def values
      @values
    end

    def where_values
      Array(@values[:where_values])
    end

    def order_values
      Array(@values[:order_values])
    end

    def select_values
      Array(@values[:select_values])
    end

    def limit_value
      @values[:limit_value] || DEFAULT_RANGE[1]
    end

    def offset_value
      @values[:offset_value] || 0
    end

    def markets
      Array(@values[:markets])
    end

    def tickers_value
      Array(@values[:tickers])
    end

    def filter2
      @values[:filter2]
    end

    def none_value?
      @values[:none_value] == true
    end

    private

    def parse_total_count(raw)
      value = raw["totalCount"] if raw.is_a?(Hash)
      return value if value.is_a?(Integer) && value >= 0

      raise Error, "scanner response totalCount must be a non-negative integer"
    end

    def default_values(klass)
      {
        select_values: klass&.default_columns || default_select,
        where_values: klass&.default_where || [],
        order_values: klass&.default_order || [{ "sortBy" => "market_cap_basic", "sortOrder" => "desc" }],
        limit_value: klass&.default_limit || DEFAULT_RANGE[1],
        offset_value: 0,
        markets: Array(klass&.default_market || "america"),
        tickers: [],
        filter2: deep_dup(klass&.default_filter2 || STOCK_TYPE_FILTER2),
        none_value: false
      }
    end

    def default_select
      %w[
        name close type typespecs pricescale minmov fractional minmove2 currency
        change volume relative_volume_10d_calc market_cap_basic fundamental_currency_code
        price_earnings_ttm earnings_per_share_diluted_ttm earnings_per_share_diluted_yoy_growth_ttm
        dividends_yield_current sector.tr market sector AnalystRating AnalystRating.tr
      ]
    end

    def spawn(**overrides)
      self.class.new(klass, values: deep_dup(@values).merge(overrides))
    end

    def field_name(value)
      case value
      when Field then value.name
      when Predicate then value.left
      else value.to_s
      end
    end

    def normalize_predicate(value)
      case value
      when Predicate then value.to_h
      when Hash
        if value.key?("left") || value.key?(:left)
          stringify_predicate(value)
        else
          raise ArgumentError, "use where(key: value) for hash conditions, got #{value.inspect}"
        end
      else
        raise ArgumentError, "unsupported where argument: #{value.inspect}"
      end
    end

    def stringify_predicate(hash)
      {
        "left" => hash[:left] || hash["left"],
        "operation" => hash[:operation] || hash["operation"],
        "right" => hash.key?(:right) ? hash[:right] : hash["right"]
      }
    end

    def build_condition(key, value)
      name = field_name(key)
      case value
      when Predicates::Op
        [{ "left" => name, "operation" => value.operation, "right" => unwrap_value(value.value) }]
      when Predicate
        [value.to_h.merge("left" => name)]
      when Range
        right = [value.begin, value.end]
        right[1] = right[1].pred if value.exclude_end? && right[1].respond_to?(:pred)
        [{ "left" => name, "operation" => "in_range", "right" => right }]
      when Array
        [{ "left" => name, "operation" => "in_range", "right" => value }]
      when Field, Symbol
        [{ "left" => name, "operation" => "equal", "right" => field_name(value) }]
      else
        [{ "left" => name, "operation" => "equal", "right" => value }]
      end
    end

    def unwrap_value(value)
      case value
      when Field then value.name
      when Symbol then value.to_s
      else value
      end
    end

    def sort_entry(key, dir)
      direction =
        case dir
        when :asc, "asc", true then "asc"
        when :desc, "desc", false then "desc"
        else
          raise ArgumentError, "order direction must be :asc or :desc, got #{dir.inspect}"
        end
      { "sortBy" => field_name(key), "sortOrder" => direction }
    end

    def order_payload
      order_values.first || { "sortBy" => "market_cap_basic", "sortOrder" => "desc" }
    end

    def symbols_payload
      payload = {}
      payload["tickers"] = tickers_value if tickers_value.any?
      payload
    end

    def execute(client:, cookies:, headers:, timeout:, label_product:, proxy: nil)
      http = client || Client.new(
        timeout: timeout,
        cookies: cookies,
        headers: headers,
        label_product: label_product,
        proxy: proxy
      )
      http.post(scanner_url, to_query)
    end

    def map_rows(raw)
      columns = select_values
      Array(raw["data"]).map do |item|
        values = Array(item["d"])
        row = {}
        columns.each_with_index { |column, index| row[column] = values[index] }
        # scanner primary key always comes from response key `s`
        row["ticker"] = item["s"]
        row
      end
    end

    def deep_dup(value)
      case value
      when Hash then value.each_with_object({}) { |(k, v), memo| memo[k] = deep_dup(v) }
      when Array then value.map { |item| deep_dup(item) }
      when String then value.dup
      else value
      end
    end
  end
end
