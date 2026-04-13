require "minitest/autorun"
require "ostruct"

require "asc_tooling"

ENV_MISSING = Object.new

def with_env(overrides)
  original_values = overrides.keys.to_h do |key|
    [key, ENV.key?(key) ? ENV[key] : ENV_MISSING]
  end

  overrides.each do |key, value|
    value.nil? ? ENV.delete(key) : ENV[key] = value
  end

  yield
ensure
  original_values.each do |key, value|
    if value.equal?(ENV_MISSING)
      ENV.delete(key)
    else
      ENV[key] = value
    end
  end
end
