require 'metasploit/framework/data_service'
require 'metasploit/framework/data_service/remote/http/data_service_auto_loader'
require 'net/http'
require 'net/https'
require 'uri'

#
# Parent data service for managing metasploit data in/on a separate process/machine over HTTP(s)
#
module Metasploit
module Framework
module DataService
class RemoteHTTPDataService
  include Metasploit::Framework::DataService
  include DataServiceAutoLoader

  ONLINE_TEST_URL = "/api/v1/online"
  EXEC_ASYNC = { :exec_async => true }
  GET_REQUEST = 'GET'
  POST_REQUEST = 'POST'
  DELETE_REQUEST = 'DELETE'

  #
  # @param [String] endpoint A valid http or https URL. Cannot be nil
  #
  def initialize(endpoint, https_opts = {})
    validate_endpoint(endpoint)
    @endpoint = URI.parse(endpoint)
    @https_opts = https_opts
    build_client_pool(5)
  end

  #
  # POST data to the HTTP endpoint and don't wait for the endpoint to process the data before getting a response
  #
  # @param path - The URI path to send the request
  # @param data_hash - A hash representation of the object to be posted. Cannot be nil or empty.
  # @param query - A hash representation of the URI query data. Key-value pairs will be URL-encoded.
  #
  # @return A wrapped response (ResponseWrapper), see below.
  #
  def post_data_async(path, data_hash, query = nil)
    make_request(POST_REQUEST, path, data_hash.merge(EXEC_ASYNC), query)
  end

  #
  # POST data to the HTTP endpoint
  #
  # @param path - The URI path to send the request
  # @param data_hash - A hash representation of the object to be posted. Cannot be nil or empty.
  # @param query - A hash representation of the URI query data. Key-value pairs will be URL-encoded.
  #
  # @return A wrapped response (ResponseWrapper), see below.
  #
  def post_data(path, data_hash, query = nil)
    make_request(POST_REQUEST, path, data_hash, query)
  end

  #
  # GET data from the HTTP endpoint
  #
  # @param path - The URI path to send the request
  # @param data_hash - A hash representation of the object to be included. Can be nil or empty.
  # @param query - A hash representation of the URI query data. Key-value pairs will be URL-encoded.
  #
  # @return A wrapped response (ResponseWrapper), see below.
  #
  def get_data(path, data_hash = nil, query = nil)
    make_request(GET_REQUEST, path, data_hash, query)
  end

  #
  # Send DELETE request to delete the specified resource from the HTTP endpoint
  #
  # @param path - The URI path to send the request
  # @param data_hash - A hash representation of the object to be deleted. Cannot be nil or empty.
  # @param query - A hash representation of the URI query data. Key-value pairs will be URL-encoded.
  #
  # @return A wrapped response (ResponseWrapper), see below.
  #
  def delete_data(path, data_hash, query = nil)
    make_request(DELETE_REQUEST, path, data_hash, query)
  end

  #
  # Make the specified request_type
  #
  # @param request_type - A string representation of the HTTP method
  # @param path - The URI path to send the request
  # @param data_hash - A hash representation of the object to be included in the request. Cannot be nil or empty.
  # @param query - A hash representation of the URI query data. Key-value pairs will be URL-encoded.
  #
  # @return A wrapped response (ResponseWrapper)
  #
  def make_request(request_type, path, data_hash = nil, query = nil)
    begin
      query_str = (!query.nil? && !query.empty?) ? URI.encode_www_form(query) : nil
      uri = URI::HTTP::build({path: path, query: query_str})
      puts "#{Time.now} - HTTP #{request_type} request to #{uri.request_uri} with #{data_hash ? data_hash : "nil"}"

      client = @client_pool.pop()
      case request_type
        when GET_REQUEST
          request = Net::HTTP::Get.new(uri.request_uri)
        when POST_REQUEST
          request = Net::HTTP::Post.new(uri.request_uri)
        when DELETE_REQUEST
          request = Net::HTTP::Delete.new(uri.request_uri)
        else
          raise Exception, 'A request_type must be specified'
      end
      built_request = build_request(request, data_hash)
      response = client.request(built_request)

      case response
        when Net::HTTPOK
          # puts 'request sent successfully'
          return SuccessResponse.new(response)
        else
          puts "HTTP #{request_type} request: #{uri.request_uri} failed with code: #{response.code} message: #{response.body}"
          return FailedResponse.new(response)
      end
    rescue EOFError => e
      puts "ERROR: No data was returned from the server."
      puts "Backtrace: #{e.message}"
      e.backtrace.each { |line| puts "#{line}\n"}
      return FailedResponse.new("")
    rescue Exception => e
      puts "Problem with HTTP #{request_type} request: #{e.message}"
      e.backtrace.each { |line| puts "#{line}\n" }
    ensure
      @client_pool << client
    end
  end

  #
  # TODO: fix this
  #
  def active
    return true
  end

  # def do_nl_search(search)
  #   search_item = search.query.split(".")[0]
  #   case search_item
  #     when "host"
  #       do_host_search(search)
  #   end
  # end

  # def active
  #   begin
  #     request_opts = {'method' => 'GET', 'uri' => ONLINE_TEST_URL}
  #     request = @client.request_raw(request_opts)
  #     response = @client._send_recv(request)
  #     if response.code == 200
  #       try_sound_effect()
  #       return true
  #     else
  #       puts "request failed with code: #{response.code} message: #{response.message}"
  #       return false
  #     end
  #   rescue Exception => e
  #     puts "Unable to contact goliath service: #{e.message}"
  #     return false
  #   end
  # end

  def name
    "remote_data_service: (#{@endpoint})"
  end

  def set_header(key, value)
    @headers = Hash.new() if @headers.nil?

    @headers[key] = value
  end

  #########
  protected
  #########

  #
  # Simple response wrapper
  #
  class ResponseWrapper
    attr_reader :response
    attr_reader :expected

    def initialize(response, expected)
      @response = response
      @expected = expected
    end
  end

  #
  # Failed response wrapper
  #
  class FailedResponse < ResponseWrapper
    def initialize(response)
      super(response, false)
    end
  end

  #
  # Success response wrapper
  #
  class SuccessResponse < ResponseWrapper
    def initialize(response)
      super(response, true)
    end
  end

  #######
  private
  #######

  def validate_endpoint(endpoint)
    raise 'Endpoint cannot be nil' if endpoint.nil?
  end

  def append_workspace(data_hash)
    workspace = data_hash[:workspace]
    workspace = data_hash.delete(:wspace) unless workspace

    if workspace && (workspace.is_a?(OpenStruct) || workspace.is_a?(::Mdm::Workspace))
      data_hash[:workspace] = workspace.name
    end

    data_hash[:workspace] = current_workspace_name if workspace.nil?

    data_hash
  end

  def build_request(request, data_hash)
    request.content_type = 'application/json'
    if !data_hash.nil? && !data_hash.empty?
      data_hash.each do |k,v|
        if v.is_a?(Msf::Session)
          puts "#{Time.now} - DEBUG: Dropping Msf::Session object before converting to JSON."
          puts "data_hash is #{data_hash}"
          puts "Callstack:"
          caller.each { |line| puts "#{line}\n"}
          data_hash.delete(k)
        end
      end
      json_body = append_workspace(data_hash).to_json
      request.body = json_body
    end

    if !@headers.nil? && !@headers.empty?
      @headers.each do |key, value|
        request[key] = value
      end
    end

    request
  end

  def build_client_pool(size)
    @client_pool = Queue.new()
    (1..size).each {
      http = Net::HTTP.new(@endpoint.host, @endpoint.port)
      if @endpoint.is_a?(URI::HTTPS)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        unless @https_opts.empty?
          if @https_opts[:skip_verify]
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          else
            # https://stackoverflow.com/questions/22093042/implementing-https-certificate-pubkey-pinning-with-ruby
            user_passed_cert = OpenSSL::X509::Certificate.new(File.read(@https_opts[:cert]))

            http.verify_callback = lambda do |preverify_ok, cert_store|
              server_cert = cert_store.chain[0]
              return true unless server_cert.to_der == cert_store.current_cert.to_der
              same_public_key?(server_cert, user_passed_cert)
            end
          end
        end
      end
      @client_pool << http
    }
  end

  # Tells us whether the private keys on the passed certificates match
  # and use the same algo
  def same_public_key?(ref_cert, actual_cert)
    pkr, pka = ref_cert.public_key, actual_cert.public_key

    # First check if the public keys use the same crypto...
    return false unless pkr.class == pka.class
    # ...and then - that they have the same contents
    return false unless pkr.to_pem == pka.to_pem

    true
  end

  def try_sound_effect()
    sound_file = ::File.join(Msf::Config.data_directory, "sounds", "Goliath_Online_Sound_Effect.wav")
    Rex::Compat.play_sound(sound_file)
  end

end
end
end
end

