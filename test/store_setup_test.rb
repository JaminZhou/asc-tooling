require_relative "test_helper"

class ASCToolingStoreSetupTest < Minitest::Test
  FakeVersion = Struct.new(:id, :version_string, :app_store_state, :release_type, keyword_init: true)

  class FakeClient
    attr_reader :requests, :updates

    def initialize(primary_category: nil, secondary_category: nil, age_attrs: {}, review_detail: nil, release_type: "AFTER_APPROVAL")
      @app = OpenStruct.new(id: "app-1", name: "Test App", bundle_id: "com.test.app")
      @app_info = OpenStruct.new(
        id: "info-1",
        raw: {
          "attributes" => {
            "state" => "PREPARE_FOR_SUBMISSION",
            "appStoreAgeRating" => age_attrs == stringified_4_plus ? "FOUR_PLUS" : nil
          }
        }
      )
      @version = FakeVersion.new(
        id: "version-1",
        version_string: "1.0.0",
        app_store_state: "PREPARE_FOR_SUBMISSION",
        release_type: release_type
      )
      @primary_category = primary_category
      @secondary_category = secondary_category
      @age_attrs = age_attrs
      @review_detail = review_detail
      @requests = []
      @updates = []
    end

    def platform(value)
      { "ios" => "IOS", "macos" => "MAC_OS" }.fetch(value)
    end

    def find_app!(_bundle_id) = @app

    def fetch_edit_app_info!(_app) = @app_info

    def find_version!(_app, platform:, app_version:)
      raise "unexpected platform #{platform}" unless %w[IOS MAC_OS].include?(platform)
      raise "unexpected app version #{app_version}" unless app_version == "1.0.0"

      @version
    end

    def update_resource(type, id, attributes:)
      @updates << { type: type, id: id, attributes: attributes }
    end

    def request_json(method, path, params: nil, body: nil)
      @requests << { method: method, path: path, params: params, body: body }

      case [method, path]
      when ["GET", "/v1/appInfos/info-1/primaryCategory"]
        category_response(@primary_category)
      when ["GET", "/v1/appInfos/info-1/secondaryCategory"]
        category_response(@secondary_category)
      when ["GET", "/v1/appInfos/info-1/ageRatingDeclaration"]
        { "data" => { "id" => "age-1", "type" => "ageRatingDeclarations", "attributes" => @age_attrs } }
      when ["GET", "/v1/appCategories"]
        {
          "data" => %w[SHOPPING UTILITIES].map do |id|
            { "id" => id, "type" => "appCategories", "attributes" => { "platforms" => ["IOS"] } }
          end
        }
      when ["PATCH", "/v1/appInfos/info-1"]
        { "data" => { "id" => "info-1", "type" => "appInfos" } }
      when ["PATCH", "/v1/ageRatingDeclarations/age-1"]
        { "data" => { "id" => "age-1", "type" => "ageRatingDeclarations" } }
      when ["GET", "/v1/appStoreVersions/version-1/appStoreReviewDetail"]
        { "data" => @review_detail }
      when ["POST", "/v1/appStoreReviewDetails"], ["PATCH", "/v1/appStoreReviewDetails/review-1"]
        { "data" => { "id" => "review-1", "type" => "appStoreReviewDetails" } }
      when ["GET", "/v1/apps/app-1/appPriceSchedule"], ["GET", "/v1/apps/app-1/appAvailabilityV2"]
        { "data" => nil }
      when ["GET", "/v1/apps/app-1/appPricePoints"]
        {
          "data" => [
            { "id" => "free-price", "type" => "appPricePoints", "attributes" => { "customerPrice" => "0.0" } },
            { "id" => "paid-price", "type" => "appPricePoints", "attributes" => { "customerPrice" => "0.99" } }
          ]
        }
      else
        raise "unexpected request: #{method} #{path}"
      end
    end

    def format_api_errors(_payload) = ""

    private

    def category_response(id)
      return { "data" => nil } unless id

      { "data" => { "id" => id, "type" => "appCategories" } }
    end

    def stringified_4_plus
      ASCTooling::StoreSetup::AGE_RATING_TEMPLATES.fetch("4-plus").transform_keys(&:to_s)
    end
  end

  def test_apply_writes_release_type_category_and_age_rating
    client = FakeClient.new
    setup = build_store_setup(
      client,
      release_type: "manual",
      primary_category: "SHOPPING",
      age_rating_template: "4-plus"
    )

    stdout, = capture_io { setup.send(:apply) }

    assert_equal(
      [{ type: "appStoreVersions", id: "version-1", attributes: { releaseType: "MANUAL" } }],
      client.updates
    )
    category_request = client.requests.find { |request| request[:method] == "PATCH" && request[:path] == "/v1/appInfos/info-1" }
    assert_equal(
      { data: { type: "appCategories", id: "SHOPPING" } },
      category_request.dig(:body, :data, :relationships, :primaryCategory)
    )
    age_request = client.requests.find { |request| request[:method] == "PATCH" && request[:path] == "/v1/ageRatingDeclarations/age-1" }
    assert_equal ASCTooling::StoreSetup::AGE_RATING_TEMPLATES.fetch("4-plus"), age_request.dig(:body, :data, :attributes)
    assert_includes stdout, "Updated release type to MANUAL"
    assert_includes stdout, "Updated category: primary=SHOPPING"
    assert_includes stdout, "Updated age rating declaration with 4-plus"
  end

  def test_apply_skips_review_detail_creation_without_complete_contact
    client = FakeClient.new
    setup = build_store_setup(
      client,
      review_contact_first_name: "Jamin",
      review_contact_last_name: "Zhou",
      review_contact_email: "me@example.com",
      review_notes: "No login."
    )

    stdout, = capture_io { setup.send(:apply) }

    assert_includes stdout, "Skipped review detail"
    refute(
      client.requests.any? { |request| request[:method] == "POST" && request[:path] == "/v1/appStoreReviewDetails" }
    )
  end

  def test_apply_creates_review_detail_when_contact_is_complete
    client = FakeClient.new
    setup = build_store_setup(
      client,
      review_contact_first_name: "Jamin",
      review_contact_last_name: "Zhou",
      review_contact_phone: "+1 555 0100",
      review_contact_email: "me@example.com",
      review_notes: "No login.",
      clear_demo_account: true
    )

    stdout, = capture_io { setup.send(:apply) }

    request = client.requests.find { |item| item[:method] == "POST" && item[:path] == "/v1/appStoreReviewDetails" }
    attrs = request.dig(:body, :data, :attributes)
    assert_equal "Jamin", attrs[:contactFirstName]
    assert_equal "+1 555 0100", attrs[:contactPhone]
    assert_equal false, attrs[:demoAccountRequired]
    assert_nil attrs[:demoAccountName]
    assert_equal "version-1", request.dig(:body, :data, :relationships, :appStoreVersion, :data, :id)
    assert_includes stdout, "Created App Review detail"
  end

  def test_apply_skips_new_review_detail_without_explicit_demo_account_state
    client = FakeClient.new
    setup = build_store_setup(
      client,
      review_contact_first_name: "Jamin",
      review_contact_last_name: "Zhou",
      review_contact_phone: "+1 555 0100",
      review_contact_email: "me@example.com",
      review_notes: "No login."
    )

    stdout, = capture_io { setup.send(:apply) }

    assert_includes stdout, "pass --no-demo-account or --demo-account-required"
    refute(
      client.requests.any? { |request| request[:method] == "POST" && request[:path] == "/v1/appStoreReviewDetails" }
    )
  end

  def test_apply_creates_review_detail_with_required_demo_account
    client = FakeClient.new
    setup = build_store_setup(
      client,
      review_contact_first_name: "Jamin",
      review_contact_last_name: "Zhou",
      review_contact_phone: "+1 555 0100",
      review_contact_email: "me@example.com",
      review_notes: "Use the demo login.",
      demo_account_required: true,
      demo_account_name: "reviewer@example.com",
      demo_account_password: "secret"
    )

    capture_io { setup.send(:apply) }

    request = client.requests.find { |item| item[:method] == "POST" && item[:path] == "/v1/appStoreReviewDetails" }
    attrs = request.dig(:body, :data, :attributes)
    assert_equal true, attrs[:demoAccountRequired]
    assert_equal "reviewer@example.com", attrs[:demoAccountName]
    assert_equal "secret", attrs[:demoAccountPassword]
  end

  def test_status_summary_reports_template_match_and_free_price_point
    client = FakeClient.new(
      primary_category: "SHOPPING",
      age_attrs: ASCTooling::StoreSetup::AGE_RATING_TEMPLATES.fetch("4-plus").transform_keys(&:to_s),
      release_type: "MANUAL"
    )
    setup = build_store_setup(client, age_rating_template: "4-plus")

    summary = setup.send(:status_summary)

    assert_equal "SHOPPING", summary.dig(:category, :primary)
    assert_equal true, summary.dig(:age_rating, :template_match)
    assert_equal "free-price", summary.dig(:pricing, :free_price_point_id)
    assert_equal false, summary.dig(:availability, :present)
  end

  private

  def build_store_setup(client, options = {})
    setup = ASCTooling::StoreSetup.allocate
    setup.instance_variable_set(
      :@options,
      {
        bundle_id: "com.test.app",
        app_version: "1.0.0",
        platform: "ios",
        price_base_territory: "USA",
        dry_run: false,
        json: false,
        clear_demo_account: false
      }.merge(options)
    )
    setup.instance_variable_set(:@asc, client)
    setup
  end
end
