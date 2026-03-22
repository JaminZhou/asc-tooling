module ASCTooling
  # Port the reusable logic from NightOwl/scripts/asc_client.rb into this class.
  #
  # Expected responsibilities:
  # - App Store Connect API key authentication
  # - shared Spaceship / raw ASC request helpers
  # - app/version/localization lookup helpers
  class Client
    def self.source_hint
      "Port from NightOwl/scripts/asc_client.rb"
    end
  end
end
