# frozen_string_literal: true

require "spec_helper"

RSpec.describe TradingviewScreener::ScreenData do
  def fixture(name)
    JSON.parse(File.read(File.expand_path("../fixtures/screen_data/#{name}.json", __dir__)))
  end

  let(:screen_data) do
    {
      "id" => "example1",
      "title" => "Momentum Trend Long",
      "market_settings" => {
        "markets" => ["america"],
        "is_primary_listing" => true
      },
      "sort_column" => { "id" => "PreMarketVolume", "params" => {} },
      "sort_direction" => "desc",
      "filters" => [
        {
          "left" => { "column" => { "id" => "Price", "params" => {} } },
          "right" => { "left" => 10, "right" => 300 },
          "operation" => { "type" => "between" },
          "target" => "value",
          "type" => "Condition"
        },
        {
          "left" => { "column" => { "id" => "MarketCap", "params" => {} } },
          "right" => { "left" => 1_000_000_000, "right" => nil },
          "operation" => { "type" => "between" },
          "target" => "value",
          "type" => "Condition"
        },
        {
          "left" => { "column" => { "id" => "AverageTrueRangePercent", "params" => { "length" => "14" } } },
          "right" => { "value" => 1 },
          "operation" => { "type" => "above" },
          "target" => "value",
          "type" => "Condition"
        },
        {
          "left" => { "column" => { "id" => "AverageTrueRangePercent", "params" => { "length" => "14" } } },
          "right" => { "value" => 6 },
          "operation" => { "type" => "below" },
          "target" => "value",
          "type" => "Condition"
        },
        {
          "left" => { "column" => { "id" => "Price", "params" => {} } },
          "right" => { "column" => { "id" => "Ma", "params" => { "length" => "20" } } },
          "operation" => { "type" => "above" },
          "target" => "Ma",
          "type" => "Condition"
        },
        {
          "left" => { "column" => { "id" => "RelativeVolumeAtTime", "params" => {} } },
          "right" => { "value" => 1.1 },
          "operation" => { "type" => "above" },
          "target" => "value",
          "type" => "Condition"
        },
        {
          "left" => { "column" => { "id" => "PreMarketVolume", "params" => {} } },
          "right" => { "value" => 30_000 },
          "operation" => { "type" => "above" },
          "target" => "value",
          "type" => "Condition"
        },
        {
          "left" => { "column" => { "id" => "PriceAvgVolume", "params" => { "interval" => "Interval10D" } } },
          "right" => { "value" => 50_000_000 },
          "operation" => { "type" => "above" },
          "target" => "value",
          "type" => "Condition"
        },
        {
          "left" => { "column" => { "id" => "Change", "params" => {} } },
          "right" => { "value" => nil },
          "operation" => { "type" => "above" },
          "target" => "value",
          "type" => "Condition"
        },
        {
          "left" => { "column" => { "id" => "Sector", "params" => {} } },
          "right" => { "values" => [] },
          "type" => "CheckboxGroup"
        }
      ],
      "default_custom_column_set" => [
        { "id" => "TickerUniversal", "params" => {} },
        { "id" => "Price", "params" => {} },
        { "id" => "PreMarketVolume", "params" => {} }
      ]
    }
  end

  it "converts screen_data filters into scanner payload" do
    payload = described_class.to_payload(screen_data)

    expect(payload["markets"]).to eq(["america"])
    expect(payload["sort"]).to eq("sortBy" => "premarket_volume", "sortOrder" => "desc")
    expect(payload["range"]).to eq([0, 100])
    expect(payload["columns"]).to include(
      "ticker-view", "close", "premarket_volume", "type",
      "change", "volume", "relative_volume_10d_calc", "sector",
      "AnalystRating", "AnalystRating.tr", "premarket_change"
    )
    expect(payload["filter"]).to include(
      hash_including("left" => "close", "operation" => "in_range", "right" => [10, 300]),
      hash_including("left" => "market_cap_basic", "operation" => "egreater", "right" => 1_000_000_000),
      hash_including("left" => "ATRP", "operation" => "greater", "right" => 1),
      hash_including("left" => "ATRP", "operation" => "less", "right" => 6),
      hash_including("left" => "close", "operation" => "greater", "right" => "SMA20"),
      hash_including("left" => "relative_volume_intraday|5", "operation" => "greater", "right" => 1.1),
      hash_including("left" => "premarket_volume", "operation" => "greater", "right" => 30_000),
      hash_including("left" => "AvgValue.Traded_10d", "operation" => "greater", "right" => 50_000_000),
      hash_including("left" => "is_primary", "operation" => "equal", "right" => true)
    )
    # null placeholder conditions are dropped
    expect(payload["filter"]).not_to include(hash_including("left" => "change"))
  end

  it "builds a Stock relation from screen_data" do
    rel = TradingviewScreener::Stock.from_screen_data(screen_data)
    query = rel.to_query

    expect(query["filter"]).to include(
      hash_including("left" => "close", "operation" => "greater", "right" => "SMA20")
    )
    expect(query["sort"]).to eq("sortBy" => "premarket_volume", "sortOrder" => "desc")
    expect(query["range"]).to eq([0, 100])
  end

  it "converts the HG Universe Wide price and exchange filters to canonical scanner fields" do
    payload = described_class.to_payload(fixture("hg_universe_wide"))

    expect(payload["filter"]).to eq([
      { "left" => "close", "operation" => "eless", "right" => 600 },
      { "left" => "exchange", "operation" => "in_range", "right" => %w[NASDAQ NYSE AMEX] }
    ])
    expect(payload["columns"]).to include("exchange")
    expect(payload["filter"]).not_to include(hash_including("left" => "Exchange"))
  end

  it "maps saved-screener camelCase comparison operations to scanner tokens" do
    expected_operations = {
      "aboveOrEqual" => "egreater",
      "belowOrEqual" => "eless",
      "notEqual" => "nequal",
      "inRange" => "in_range",
      "notBetween" => "not_in_range",
      "crossesAbove" => "crosses_above",
      "crossesBelow" => "crosses_below",
      "notMatch" => "nmatch",
      "notEmpty" => "nempty",
      "hasNoneOf" => "has_none_of"
    }

    expected_operations.each do |source_operation, scanner_operation|
      data = fixture("hg_universe_wide")
      condition = data.fetch("filters").first
      condition["operation"]["type"] = source_operation
      condition["right"] =
        if %w[inRange notBetween].include?(source_operation)
          { "left" => 10, "right" => 600 }
        else
          { "value" => 600 }
        end

      converted = described_class.to_payload(data).fetch("filter").first
      expect(converted.fetch("operation")).to eq(scanner_operation), source_operation
    end
  end

  it "fails fast for unknown saved-screener operations" do
    data = fixture("hg_universe_wide")
    data.fetch("filters").first.fetch("operation")["type"] = "approximately"

    expect { described_class.to_payload(data) }
      .to raise_error(
        TradingviewScreener::ScreenData::ConversionError,
        'unsupported screen_data operation: "approximately"'
      )
  end

  it "parses screen_data from HTML" do
    html = <<~HTML
      <html><script>
        window.initData = window.initData || {};
        window.initData.screen_data = #{JSON.generate(screen_data)};
        window.initData.onScreenerStandalonePage = true;
      </script></html>
    HTML

    parsed = described_class.parse_html(html)
    expect(parsed["id"]).to eq("example1")
    expect(described_class.to_payload(parsed)["filter"]).to include(
      hash_including("left" => "AvgValue.Traded_10d", "right" => 50_000_000)
    )
  end
end
