require_relative "test_helper"

class ASCToolingBetaTest < Minitest::Test
  class FakeClient
    attr_reader :requests

    def initialize(app:, groups: [], testers: [])
      @app = app
      @groups = groups
      @testers = testers
      @requests = []
    end

    def platform(_value) = "MAC_OS"
    def find_app!(_bundle_id) = @app

    def build_candidates(_app_id, _version = nil, limit: 20)
      [{ "id" => "build-1", "attributes" => { "version" => "42", "processingState" => "VALID" } }]
    end

    def request_json(method, path, params: nil, body: nil)
      @requests << { method: method, path: path, params: params, body: body }
      { "data" => [] }
    end

    def format_api_errors(_payload) = ""
  end

  def test_create_group_dry_run_does_not_call_api
    app = OpenStruct.new(id: "app-1", name: "Test", bundle_id: "com.test")
    client = FakeClient.new(app: app)
    beta = build_beta(client, command: "create-group", group_name: "TestGroup", dry_run: true)

    stdout, = capture_io { beta.send(:create_group) }

    assert_includes stdout, "Dry run"
    assert_includes stdout, "TestGroup"
    # Only the beta_groups lookup request, no POST
    post_requests = client.requests.select { |r| r[:method] == "POST" }
    assert_equal 0, post_requests.length
  end

  def test_create_group_skips_if_already_exists
    app = OpenStruct.new(id: "app-1", name: "Test", bundle_id: "com.test")
    client = FakeClient.new(app: app)

    # Override request_json to return existing group
    client.define_singleton_method(:request_json) do |method, path, params: nil, body: nil|
      @requests << { method: method, path: path }
      if path == "/v1/betaGroups" && method == "GET"
        { "data" => [{ "id" => "g-1", "attributes" => { "name" => "TestGroup" } }] }
      else
        { "data" => {} }
      end
    end

    beta = build_beta(client, command: "create-group", group_name: "TestGroup")

    stdout, = capture_io { beta.send(:create_group) }

    assert_includes stdout, "already exists"
    post_requests = client.requests.select { |r| r[:method] == "POST" }
    assert_equal 0, post_requests.length
  end

  private

  def build_beta(client, options = {})
    beta = ASCTooling::Beta.allocate
    beta.instance_variable_set(
      :@options,
      {
        bundle_id: "com.test",
        platform: "macos"
      }.merge(options)
    )
    beta.instance_variable_set(:@asc, client)
    beta
  end
end
