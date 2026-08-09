# frozen_string_literal: true

require "spec_helper"

RSpec.describe TradingviewScreener::ScreenData do
  def fixture(name)
    JSON.parse(File.read(File.expand_path("../fixtures/screen_data/#{name}.json", __dir__)))
  end

  def scanner_fields(*extra)
    aliases = TradingviewScreener::ScreenData::FieldContract::PROJECTION_ALIASES
    fields =
      TradingviewScreener::ScreenData::Converter::DEFAULT_COLUMNS +
      TradingviewScreener::ScreenData::Converter::REQUIRED_METADATA_COLUMNS +
      %w[type typespecs] + extra.flatten
    fields.map(&:to_s).uniq.reject { |field| aliases.include?(field) }
  end

  def metainfo_body(*extra)
    JSON.generate(
      "fields" => scanner_fields(*extra).map { |name| { "n" => name, "t" => "text" } }
    )
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
      "nequal" => "nequal",
      "inRange" => "in_range",
      "outside" => "not_in_range",
      "crossesUp" => "crosses_above",
      "crossesDown" => "crosses_below"
    }

    expected_operations.each do |source_operation, scanner_operation|
      data = fixture("hg_universe_wide")
      condition = data.fetch("filters").first
      condition["operation"]["type"] = source_operation
      condition["right"] =
        if %w[inRange outside].include?(source_operation)
          { "left" => 10, "right" => 600 }
        else
          { "value" => 600 }
        end

      converted = described_class.to_payload(data).fetch("filter").first
      expect(converted.fetch("operation")).to eq(scanner_operation), source_operation
    end
  end

  it "preserves TradingView's inclusive one-sided outside range semantics" do
    data = fixture("hg_universe_wide")
    condition = data.fetch("filters").first
    condition.fetch("operation")["type"] = "outside"

    condition["right"] = { "left" => nil, "right" => 600 }
    expect(described_class.to_payload(data).fetch("filter").first)
      .to eq("left" => "close", "operation" => "egreater", "right" => 600)

    condition["right"] = { "left" => 10, "right" => nil }
    expect(described_class.to_payload(data).fetch("filter").first)
      .to eq("left" => "close", "operation" => "eless", "right" => 10)
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

  it "validates filter and sort fields against scanner metainfo over HTTP" do
    metainfo_url = "https://scanner.tradingview.com/america/metainfo"
    request = stub_request(:get, metainfo_url).to_return(
      status: 200,
      body: metainfo_body("exchange")
    )

    payload = described_class.to_validated_payload(fixture("hg_universe_wide"))

    expect(payload["filter"]).to eq([
      { "left" => "close", "operation" => "eless", "right" => 600 },
      { "left" => "exchange", "operation" => "in_range", "right" => %w[NASDAQ NYSE AMEX] }
    ])
    expect(request).to have_been_requested.once
  end

  it "always validates saved screener URL conversions through the HTTP metainfo contract" do
    screener_url = "https://www.tradingview.com/screener/hg-universe-wide/"
    data = fixture("hg_universe_wide")
    html = <<~HTML
      <script>
        window.initData.screen_data = #{JSON.generate(data)};
        window.initData.onScreenerStandalonePage = true;
      </script>
    HTML
    page_request = stub_request(:get, screener_url).to_return(status: 200, body: html)
    metainfo_request = stub_request(:get, "https://scanner.tradingview.com/america/metainfo").to_return(
      status: 200,
      body: metainfo_body("exchange")
    )

    fetched = described_class.fetch(screener_url)

    expect(fetched.fetch("payload").fetch("filter").first)
      .to eq("left" => "close", "operation" => "eless", "right" => 600)
    expect(page_request).to have_been_requested.once
    expect(metainfo_request).to have_been_requested.once
  end

  it "fails fast when a mapped query field is absent from scanner metainfo" do
    contract = described_class::FieldContract.new(
      "america" => %w[close market_cap_basic type typespecs]
    )

    expect { described_class.to_payload(fixture("hg_universe_wide"), field_contract: contract) }
      .to raise_error(
        TradingviewScreener::ScreenData::FieldContractError,
        'scanner field "exchange" is absent from metainfo for: america'
      )
  end

  it "fails fast for unknown saved-screener column ids instead of passing them through" do
    data = fixture("hg_universe_wide")
    data.fetch("filters").first.fetch("left").fetch("column")["id"] = "LegacyPrice"

    expect { described_class.to_payload(data) }
      .to raise_error(
        TradingviewScreener::ScreenData::ConversionError,
        'unsupported screen_data column id: "LegacyPrice"'
      )
  end

  it "uses the generated bundle map for simple scanner fields" do
    data = fixture("hg_universe_wide")
    condition = data.fetch("filters").first
    condition.fetch("left").fetch("column")["id"] = "Gap"
    contract = described_class::FieldContract.new(
      "america" => scanner_fields("gap", "exchange")
    )

    converted = described_class.to_payload(data, field_contract: contract).fetch("filter").first

    expect(converted).to eq("left" => "gap", "operation" => "eless", "right" => 600)
    expect(described_class::GENERATED_COLUMN_BASE_MAP.size).to be >= 400
  end

  it "maps parameterized financial and interval fields explicitly" do
    converter = described_class::Converter.new({})

    expect(converter.send(:map_column_id, "Beta", "interval" => "Interval5Y")).to eq("beta_5_year")
    expect(converter.send(:map_column_id, "ReturnOnEquity", "fiscalPeriod" => "ttm"))
      .to eq("return_on_equity_fq")
    expect(converter.send(:map_column_id, "EpsDilutedGrowth", "period" => "YoYAnnual"))
      .to eq("earnings_per_share_diluted_yoy_growth_fy")
    expect(converter.send(:map_column_id, "RevenueGrowth", "period" => "FiveYCAGR"))
      .to eq("total_revenue_cagr_5y")
  end

  it "rejects malformed metainfo instead of skipping field validation" do
    stub_request(:get, "https://scanner.tradingview.com/america/metainfo").to_return(
      status: 200,
      body: JSON.generate("fields" => nil)
    )

    expect { described_class.to_validated_payload(fixture("hg_universe_wide")) }
      .to raise_error(
        TradingviewScreener::ScreenData::FieldContractError,
        "invalid america metainfo: fields must be an array"
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
