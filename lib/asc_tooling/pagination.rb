module ASCTooling
  module Pagination
    def paginated_resources(path, params: {}, limit: Client::DEFAULT_PAGE_LIMIT)
      resources = []
      next_path = path
      next_params = params.merge("limit" => limit.to_s)

      loop do
        response = request_json("GET", next_path, params: next_params)
        resources.concat(response.fetch("data", []))

        next_link = response.dig("links", "next")
        break if Client.blank?(next_link)

        uri = URI(next_link)
        next_path = uri.path
        next_params = URI.decode_www_form(uri.query || "").to_h
      end

      resources
    end
  end
end
