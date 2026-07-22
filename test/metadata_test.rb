require_relative "test_helper"
require "tmpdir"

class ASCToolingMetadataTest < Minitest::Test
  class FakeClient
    attr_reader :requests, :update_calls, :read_version_calls, :editable_version_calls,
                :app_info_state_calls

    def initialize(app:, version:, localization: nil, app_info_localization: nil)
      @app = app
      @version = version
      @localization = localization
      @app_info_localization = app_info_localization
      @requests = []
      @update_calls = []
      @read_version_calls = []
      @editable_version_calls = []
      @app_info_state_calls = []
    end

    def platform(_value) = "MAC_OS"
    def find_app!(_bundle_id) = @app

    def find_version!(_app, platform:, app_version: nil)
      @read_version_calls << { platform: platform, app_version: app_version }
      @version
    end

    def find_editable_version!(_app, platform:, app_version: nil)
      @editable_version_calls << { platform: platform, app_version: app_version }
      @version
    end

    def find_version_localization(_version, _locale) = @localization
    def find_or_create_version_localization!(_version, _locale) = @localization

    def find_app_info_localization(_app, _locale, states: nil)
      @app_info_state_calls << states
      [OpenStruct.new(id: "info-1"), @app_info_localization]
    end

    def find_or_create_app_info_localization!(_app, _locale, name: nil)
      [OpenStruct.new(id: "info-1"), @app_info_localization]
    end

    def update_resource(type, id, attributes:)
      @update_calls << { type: type, id: id, attributes: attributes }
    end

    def format_api_errors(_payload) = ""
  end

  def test_resolved_attributes_reads_from_file
    Dir.mktmpdir do |dir|
      file_path = File.join(dir, "description.txt")
      File.write(file_path, "  My app description  \n")

      metadata = build_metadata(nil, description_file: file_path)
      attrs = metadata.send(:resolved_attributes, ASCTooling::Metadata::VERSION_FIELD_OPTIONS)

      assert_equal "My app description", attrs[:description]
    end
  end

  def test_resolved_attributes_prefers_inline_over_file
    Dir.mktmpdir do |dir|
      file_path = File.join(dir, "description.txt")
      File.write(file_path, "from file")

      metadata = build_metadata(nil, description: "from option", description_file: file_path)
      attrs = metadata.send(:resolved_attributes, ASCTooling::Metadata::VERSION_FIELD_OPTIONS)

      assert_equal "from option", attrs[:description]
    end
  end

  def test_status_reads_released_version_without_editable_filter
    app = OpenStruct.new(id: "app-1", name: "Test", bundle_id: "com.test")
    version = OpenStruct.new(
      id: "v-1",
      version_string: "1.10.0",
      app_store_state: "READY_FOR_SALE",
      copyright: "2026 Test"
    )
    localization = OpenStruct.new(
      description: "Description",
      keywords: "keywords",
      marketing_url: "https://example.com",
      promotional_text: "Promotional text",
      support_url: "https://example.com/support",
      whats_new: "What's New"
    )
    client = FakeClient.new(app: app, version: version, localization: localization)
    metadata = build_metadata(client, app_version: "1.10.0")

    output = capture_io { metadata.send(:print_status) }.first

    assert_includes output, "Version: 1.10.0"
    assert_includes output, "State: READY_FOR_SALE"
    assert_equal [{ platform: "MAC_OS", app_version: "1.10.0" }], client.read_version_calls
    assert_empty client.editable_version_calls
    assert_equal [["READY_FOR_SALE"]], client.app_info_state_calls

    metadata.instance_variable_get(:@options)[:json] = true
    summary = JSON.parse(capture_io { metadata.send(:print_status) }.first)
    assert_equal "READY_FOR_SALE", summary["version_state"]
  end

  def test_status_uses_selected_submitted_state_for_app_info
    app = OpenStruct.new(id: "app-1", name: "Test", bundle_id: "com.test")
    version = OpenStruct.new(
      id: "v-1",
      version_string: "1.10.0",
      app_store_state: "PENDING_DEVELOPER_RELEASE",
      copyright: "2026 Test"
    )
    client = FakeClient.new(app: app, version: version)
    metadata = build_metadata(client, app_version: "1.10.0")

    capture_io { metadata.send(:print_status) }

    assert_equal [["PENDING_DEVELOPER_RELEASE"]], client.app_info_state_calls
    assert_empty client.editable_version_calls
  end

  def test_apply_updates_version_direct_attributes
    app = OpenStruct.new(id: "app-1", name: "Test", bundle_id: "com.test")
    version = OpenStruct.new(id: "v-1", version_string: "1.0")
    client = FakeClient.new(app: app, version: version)
    metadata = build_metadata(client, copyright: "2026 Test")

    capture_io { metadata.send(:apply) }

    assert_equal 1, client.update_calls.length
    assert_equal "appStoreVersions", client.update_calls.first[:type]
    assert_equal "v-1", client.update_calls.first[:id]
    assert_equal({ copyright: "2026 Test" }, client.update_calls.first[:attributes])
    assert_empty client.read_version_calls
    assert_equal [{ platform: "MAC_OS", app_version: nil }], client.editable_version_calls
  end

  def test_apply_updates_app_info_localization
    app = OpenStruct.new(id: "app-1", name: "Test", bundle_id: "com.test")
    version = OpenStruct.new(id: "v-1", version_string: "1.0")
    loc = OpenStruct.new(id: "loc-1")
    client = FakeClient.new(app: app, version: version, app_info_localization: loc)
    metadata = build_metadata(client, name: "New Name")

    capture_io { metadata.send(:apply) }

    assert_equal 1, client.update_calls.length
    assert_equal "appInfoLocalizations", client.update_calls.first[:type]
    assert_equal "loc-1", client.update_calls.first[:id]
  end

  private

  def build_metadata(client, options = {})
    metadata = ASCTooling::Metadata.allocate
    metadata.instance_variable_set(
      :@options,
      {
        bundle_id: "com.test",
        platform: "macos",
        locale: "en-US"
      }.merge(options)
    )
    metadata.instance_variable_set(:@asc, client)
    metadata
  end
end
