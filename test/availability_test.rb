require_relative "test_helper"

class ASCToolingAvailabilityTest < Minitest::Test
  class FakeClient
    attr_reader :requests

    def initialize(app:, territory_ids:, available_territory_ids:, available_in_new_territories: true)
      @app = app
      @territory_ids = territory_ids
      @available_territory_ids = available_territory_ids
      @available_in_new_territories = available_in_new_territories
      @requests = []
    end

    def find_app!(_bundle_id) = @app

    def request_json(method, path, params: nil, body: nil)
      @requests << { method: method, path: path, params: params, body: body }

      case path
      when "/v1/apps/#{@app.id}/appAvailabilityV2"
        {
          "data" => {
            "id" => "availability-1",
            "attributes" => {
              "availableInNewTerritories" => @available_in_new_territories
            }
          }
        }
      when "/v1/territories"
        {
          "data" => @territory_ids.map { |id| { "id" => id, "type" => "territories" } }
        }
      when "/v2/appAvailabilities/availability-1/territoryAvailabilities"
        {
          "data" => @available_territory_ids.map do |id|
            {
              "id" => encoded_territory_availability_id(id),
              "type" => "territoryAvailabilities",
              "relationships" => {
                "territory" => {
                  "data" => {
                    "type" => "territories",
                    "id" => id
                  }
                }
              }
            }
          end
        }
      else
        raise "unexpected request: #{method} #{path}"
      end
    end

    def format_api_errors(_payload) = ""

    private

    def encoded_territory_availability_id(id)
      [JSON.dump({ "t" => id })].pack("m0")
    end
  end

  def test_status_summary_is_ready_when_all_territories_are_available
    app = OpenStruct.new(id: "app-1", name: "Test", bundle_id: "com.test")
    client = FakeClient.new(app: app, territory_ids: %w[JPN USA], available_territory_ids: %w[USA JPN])
    availability = build_availability(client)

    summary = availability.send(:status_summary)

    assert_equal true, summary[:ok]
    assert_equal "ready", summary[:status]
    assert_equal 2, summary.dig(:availability, :all_territory_count)
    assert_equal 2, summary.dig(:availability, :available_territory_count)
    assert_empty summary.dig(:availability, :missing_territory_ids)
  end

  def test_status_summary_reports_missing_territories
    app = OpenStruct.new(id: "app-1", name: "Test", bundle_id: "com.test")
    client = FakeClient.new(app: app, territory_ids: %w[CAN JPN USA], available_territory_ids: %w[JPN USA])
    availability = build_availability(client)

    summary = availability.send(:status_summary)

    assert_equal false, summary[:ok]
    assert_equal "availability_gap", summary[:status]
    assert_equal 1, summary.dig(:availability, :missing_territory_count)
    assert_equal ["CAN"], summary.dig(:availability, :missing_territory_ids)
  end

  def test_status_summary_excludes_unknown_territories_from_available_count
    app = OpenStruct.new(id: "app-1", name: "Test", bundle_id: "com.test")
    client = FakeClient.new(app: app, territory_ids: %w[JPN USA], available_territory_ids: %w[JPN USA XYZ])
    availability = build_availability(client)

    summary = availability.send(:status_summary)

    assert_equal true, summary[:ok]
    assert_equal 2, summary.dig(:availability, :all_territory_count)
    assert_equal 2, summary.dig(:availability, :available_territory_count)
    assert_empty summary.dig(:availability, :missing_territory_ids)
    assert_equal ["XYZ"], summary.dig(:availability, :unknown_available_territory_ids)
  end

  def test_print_status_json_outputs_summary
    app = OpenStruct.new(id: "app-1", name: "Test", bundle_id: "com.test")
    client = FakeClient.new(app: app, territory_ids: %w[JPN USA], available_territory_ids: %w[JPN USA])
    availability = build_availability(client, json: true)

    stdout, = capture_io { availability.send(:print_status) }
    parsed = JSON.parse(stdout)

    assert_equal true, parsed["ok"]
    assert_equal "ready", parsed["status"]
    assert_equal 0, parsed.dig("availability", "missing_territory_count")
  end

  private

  def build_availability(client, options = {})
    availability = ASCTooling::Availability.allocate
    availability.instance_variable_set(
      :@options,
      {
        bundle_id: "com.test"
      }.merge(options)
    )
    availability.instance_variable_set(:@asc, client)
    availability
  end
end
