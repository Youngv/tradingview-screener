# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module TradingviewScreener
  # Convert TradingView saved-screener `window.initData.screen_data`
  # into scanner.tradingview.com scan payloads / Relations.
  module ScreenData
    module_function

    def to_payload(screen_data)
      Converter.new(screen_data).to_payload
    end

    def to_relation(screen_data, model: Stock)
      model.from_payload(to_payload(screen_data))
    end

    def parse_html(html)
      Parser.extract_screen_data(html)
    end

    def fetch(url, cookies: nil, proxy: nil, timeout: 20, headers: nil)
      Fetcher.new(cookies: cookies, proxy: proxy, timeout: timeout, headers: headers).fetch(url)
    end

    class ParseError < Error; end
    class FetchError < Error; end

    class Parser
      SCREEN_DATA_RE = /window\.initData\.screen_data\s*=\s*(\{.*?\})\s*;\s*\n\s*window\.initData\.onScreenerStandalonePage/m

      def self.extract_screen_data(html)
        text = html.to_s
        match = text.match(SCREEN_DATA_RE)
        raise ParseError, "screen_data not found in HTML" unless match

        JSON.parse(match[1])
      rescue JSON::ParserError => e
        raise ParseError, "invalid screen_data JSON: #{e.message}"
      end
    end

    class Fetcher
      def initialize(cookies: nil, proxy: nil, timeout: 20, headers: nil)
        @cookies = cookies
        @proxy = proxy
        @timeout = timeout
        @headers = headers
      end

      def fetch(url)
        client = Client.new(
          timeout: @timeout,
          cookies: @cookies,
          proxy: @proxy,
          headers: {
            "accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "user-agent" => "tradingview-screener-rb/#{VERSION}"
          }.merge(@headers || {})
        )
        html = client.get(url)
        data = Parser.extract_screen_data(html)
        {
          "url" => url,
          "screen_data" => data,
          "payload" => Converter.new(data).to_payload
        }
      end
    end

    class Converter
      COLUMN_MAP = {
        "Price" => "close",
        "Change" => "change",
        "Volume" => "volume",
        "MarketCap" => "market_cap_basic",
        "PriceToEarnings" => "price_earnings_ttm",
        "EpsDiluted" => "earnings_per_share_diluted_ttm",
        "EpsDilutedGrowth" => "earnings_per_share_diluted_yoy_growth_ttm",
        "DividendsYield" => "dividends_yield_current",
        "Sector" => "sector",
        "AnalystRating" => "AnalystRating",
        "PreMarketChange" => "premarket_change",
        "PreMarketVolume" => "premarket_volume",
        "PreMarketGap" => "premarket_gap",
        "TickerUniversal" => "ticker-view",
        "RelativeVolume" => "relative_volume_10d_calc",
        "RelativeVolumeAtTime" => "relative_volume_intraday|5",
        "AverageTrueRangePercent" => "ATRP",
        "PriceAvgVolume" => "AvgValue.Traded_10d",
        "AverageVolume" => "average_volume_10d_calc",
        "Performance" => "Perf.W",
        "RevenueGrowth" => "total_revenue_yoy_growth_ttm",
        "PriceToEarningsToGrowth" => "price_earnings_growth_ttm",
        "ReturnOnEquity" => "return_on_equity",
        "Beta" => "beta_1_year",
        "Ma" => "SMA"
      }.freeze

      SORT_MAP = {
        "PreMarketVolume" => "premarket_volume",
        "MarketCap" => "market_cap_basic",
        "Volume" => "volume",
        "Change" => "change",
        "Price" => "close",
        "PreMarketChange" => "premarket_change",
        "RelativeVolume" => "relative_volume_10d_calc"
      }.freeze

      DEFAULT_COLUMNS = %w[
        ticker-view close type typespecs pricescale minmov fractional minmove2 currency
        change volume relative_volume_10d_calc market_cap_basic fundamental_currency_code
        price_earnings_ttm earnings_per_share_diluted_ttm earnings_per_share_diluted_yoy_growth_ttm
        dividends_yield_current sector.tr market sector AnalystRating AnalystRating.tr
        premarket_change premarket_volume
      ].freeze

      def initialize(screen_data)
        @data = deep_stringify(screen_data)
      end

      def to_payload
        markets = Array(@data.dig("market_settings", "markets"))
        markets = ["america"] if markets.empty?
        filters = convert_filters(Array(@data["filters"]))
        if @data.dig("market_settings", "is_primary_listing")
          filters << { "left" => "is_primary", "operation" => "equal", "right" => true }
        end

        {
          "markets" => markets,
          "symbols" => {},
          "options" => { "lang" => "en" },
          "columns" => convert_columns(Array(@data["default_custom_column_set"])),
          "filter" => filters,
          "filter2" => deep_dup(Relation::STOCK_TYPE_FILTER2),
          "sort" => convert_sort,
          "range" => [0, 100],
          "ignore_unknown_fields" => false,
          "meta" => {
            "id" => @data["id"],
            "title" => @data["title"],
            "version" => @data["version"],
            "date_created" => @data["date_created"],
            "date_updated" => @data["date_updated"],
            "date_used" => @data["date_used"]
          }.compact
        }
      end

      private

      # Keep screen-defined columns, but always include the fields used by trading-universe metadata.
      REQUIRED_METADATA_COLUMNS = %w[
        close
        change
        volume
        relative_volume_10d_calc
        sector
        AnalystRating
        AnalystRating.tr
        premarket_change
      ].freeze

      def convert_columns(column_set)
        cols = column_set.filter_map { |item| map_column_ref(item) }
        cols = DEFAULT_COLUMNS.dup if cols.empty?
        # Ensure type fields used by filter2 compatibility remain present,
        # and always request the metadata columns consumers expect.
        (%w[type typespecs] + cols + REQUIRED_METADATA_COLUMNS).uniq
      end

      def deep_dup(value)
        case value
        when Hash then value.each_with_object({}) { |(k, v), memo| memo[k] = deep_dup(v) }
        when Array then value.map { |item| deep_dup(item) }
        when String then value.dup
        else value
        end
      end

      def convert_sort
        column = @data.dig("sort_column", "id").to_s
        direction = @data["sort_direction"].to_s.downcase == "asc" ? "asc" : "desc"
        sort_by = SORT_MAP[column] || map_column_id(column, @data.dig("sort_column", "params") || {}) || "market_cap_basic"
        {
          "sortBy" => sort_by,
          "sortOrder" => direction
        }
      end

      def convert_filters(filters)
        filters.filter_map { |filter| convert_filter(filter) }
      end

      def convert_filter(filter)
        type = filter["type"].to_s
        case type
        when "Condition"
          convert_condition(filter)
        when "CheckboxGroup"
          convert_checkbox_group(filter)
        when "Date"
          nil # relative date filters with null are inactive placeholders
        else
          nil
        end
      end

      def convert_condition(filter)
        left = map_column_ref(filter.dig("left", "column"))
        return nil if left.nil? || left == ""

        operation = filter.dig("operation", "type").to_s
        right = filter["right"]
        target = filter["target"].to_s

        if right.is_a?(Hash) && right.key?("column")
          right_col = map_column_ref(right["column"])
          return nil if right_col.nil? || right_col == ""

          return {
            "left" => left,
            "operation" => operation_name(operation, equal_ok: true),
            "right" => right_col
          }
        end

        if right.is_a?(Hash) && (right.key?("left") || right.key?("right")) && operation == "between"
          low = right["left"]
          high = right["right"]
          return nil if low.nil? && high.nil?

          if !low.nil? && !high.nil?
            return { "left" => left, "operation" => "in_range", "right" => [low, high] }
          elsif !low.nil?
            return { "left" => left, "operation" => "egreater", "right" => low }
          else
            return { "left" => left, "operation" => "eless", "right" => high }
          end
        end

        value = right.is_a?(Hash) ? right["value"] : right
        return nil if value.nil? && target == "value"

        {
          "left" => left,
          "operation" => operation_name(operation, equal_ok: true),
          "right" => value
        }
      end

      def convert_checkbox_group(filter)
        values = filter.dig("right", "values")
        return nil if values.nil? || Array(values).empty?

        left = map_column_ref(filter.dig("left", "column"))
        return nil if left.nil? || left == ""

        {
          "left" => left,
          "operation" => "in_range",
          "right" => Array(values)
        }
      end

      def operation_name(type, equal_ok: false)
        case type.to_s
        when "above", "greater" then "greater"
        when "below", "less" then "less"
        when "above_or_equal", "egreater" then "egreater"
        when "below_or_equal", "eless" then "eless"
        when "equal", "eq" then "equal"
        when "not_equal", "nequal" then "nequal"
        when "between" then "in_range"
        else
          equal_ok ? "equal" : type.to_s
        end
      end

      def map_column_ref(column)
        return nil if column.nil? || column == {} || column == ""

        map_column_id(column["id"], column["params"] || {})
      end

      def map_column_id(id, params)
        id = id.to_s
        params = deep_stringify(params || {})

        case id
        when "Ma"
          length = params["length"]
          length = "20" if length.nil? || length == ""
          "SMA#{length}"
        when "AverageTrueRangePercent"
          "ATRP"
        when "RelativeVolumeAtTime"
          # default TV intraday relative volume used by saved screens
          "relative_volume_intraday|5"
        when "RelativeVolume"
          "relative_volume_10d_calc"
        when "PriceAvgVolume"
          "AvgValue.Traded_10d"
        when "AverageVolume"
          interval = params["interval"].to_s
          case interval
          when "Interval10D" then "average_volume_10d_calc"
          when "Interval30D" then "average_volume_30d_calc"
          else "average_volume_10d_calc"
          end
        when "Performance"
          interval = params["interval"].to_s
          case interval
          when "Interval1W" then "Perf.W"
          when "Interval1M" then "Perf.1M"
          when "Interval3M" then "Perf.3M"
          when "Interval6M" then "Perf.6M"
          when "IntervalYTD" then "Perf.YTD"
          when "Interval1Y" then "Perf.Y"
          else "Perf.W"
          end
        else
          COLUMN_MAP[id] || id
        end
      end

      def deep_stringify(value)
        case value
        when Hash
          value.each_with_object({}) { |(k, v), memo| memo[k.to_s] = deep_stringify(v) }
        when Array
          value.map { |item| deep_stringify(item) }
        else
          value
        end
      end
    end
  end
end
