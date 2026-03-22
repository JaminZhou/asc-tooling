module ASCTooling
  # Port the reusable logic from NightOwl/scripts/asc_beta.rb into this class.
  #
  # Expected responsibilities:
  # - beta group status
  # - add build
  # - add tester
  # - remove tester
  class Beta
    def self.run(_argv = ARGV)
      raise NotImplementedError, "Port beta workflow from NightOwl/scripts/asc_beta.rb"
    end
  end
end
