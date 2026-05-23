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
      if path == "/v1/betaGroups" && method == "GET"
        groups = if params&.fetch("filter[id]", nil)
                   @groups.select { |group| group["id"] == params["filter[id]"] }
                 else
                   @groups
                 end
        tester_ids = groups.flat_map do |group|
          group.fetch("relationships", {}).fetch("betaTesters", {}).fetch("data", []).map { |item| item["id"] }
        end
        return {
          "data" => groups,
          "included" => @testers.select { |tester| tester_ids.include?(tester["id"]) }
        }
      end

      if path == "/v1/betaTesters" && method == "GET"
        filtered_testers = @testers.select do |tester|
          params.nil? || params["filter[email]"].nil? || tester.dig("attributes", "email") == params["filter[email]"]
        end
        return { "data" => filtered_testers }
      end

      if path == "/v1/betaTesters" && method == "POST"
        attributes = body.fetch(:data).fetch(:attributes)
        return {
          "data" => {
            "id" => "created-tester",
            "type" => "betaTesters",
            "attributes" => {
              "email" => attributes.fetch(:email),
              "firstName" => attributes.fetch(:firstName),
              "lastName" => attributes.fetch(:lastName)
            }
          }
        }
      end

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

  def test_add_tester_create_if_missing_creates_tester_in_target_group_when_global_matches_are_ambiguous
    app = OpenStruct.new(id: "app-1", name: "Test", bundle_id: "com.test")
    group = {
      "id" => "group-1",
      "attributes" => { "name" => "Internal" },
      "relationships" => { "betaTesters" => { "data" => [] } }
    }
    testers = [
      { "id" => "tester-1", "attributes" => { "email" => "tester@example.com" } },
      { "id" => "tester-2", "attributes" => { "email" => "tester@example.com" } }
    ]
    client = FakeClient.new(app: app, groups: [group], testers: testers)
    beta = build_beta(
      client,
      command: "add-tester",
      group_name: "Internal",
      email: "tester@example.com",
      create_if_missing: true,
      first_name: "Test",
      last_name: "User"
    )

    stdout, = capture_io { beta.send(:add_tester) }

    assert_includes stdout, "Added tester tester@example.com"
    create_request = client.requests.find { |request| request[:method] == "POST" && request[:path] == "/v1/betaTesters" }
    refute_nil create_request
    assert_equal "tester@example.com", create_request.dig(:body, :data, :attributes, :email)
    assert_equal "Test", create_request.dig(:body, :data, :attributes, :firstName)
    assert_equal "User", create_request.dig(:body, :data, :attributes, :lastName)
    assert_equal(
      [{ type: "betaGroups", id: "group-1" }],
      create_request.dig(:body, :data, :relationships, :betaGroups, :data)
    )
    relationship_posts = client.requests.select do |request|
      request[:method] == "POST" && request[:path].include?("/relationships/betaGroups")
    end
    assert_empty relationship_posts
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
