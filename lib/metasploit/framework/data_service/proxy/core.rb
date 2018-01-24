require 'open3'
require 'rex/ui'
require 'rex/logging'
require 'metasploit/framework/data_service/remote/http/core'
require 'metasploit/framework/data_service/proxy/data_proxy_auto_loader'

#
# Holds references to data services (@see Metasploit::Framework::DataService)
# and forwards data to the implementation set as current.
#
module Metasploit
module Framework
module DataService
class DataProxy
  include DataProxyAutoLoader

  attr_reader :usable

  def initialize(opts = {})
    @data_services = {}
    @data_service_id = 0
    @usable = false
    setup(opts)
  end

  #
  # Returns current error state
  #
  def error
    return @error if (@error)
    return @data_service.error if @data_service
    return "none"
  end

  def is_local?
    if (@data_service)
      return (@data_service.name == 'local_db_service')
    end

    return false
  end

  #
  # Determines if the data service is active
  #
  def active
    if (@data_service)
      return @data_service.active
    end

    return false
  end

  #
  # Registers a data service with the proxy and immediately
  # set as primary if online
  #
  def register_data_service(data_service, online=false)
    validate(data_service)

    puts "Registering data service: #{data_service.name}"
    data_service_id = @data_service_id += 1
    @data_services[data_service_id] = data_service
    set_data_service(data_service_id, online)
  end

  #
  # Set the data service to be used
  #
  def set_data_service(data_service_id, online=false)
    data_service = @data_services[data_service_id.to_i]
    if (data_service.nil?)
      puts "Data service with id: #{data_service_id} does not exist"
      return nil
    end

    if (!online && !data_service.active)
      puts "Data service not online: #{data_service.name}, not setting as active"
      return nil
    end

    puts "Setting active data service: #{data_service.name}"
    @data_service = data_service
  end

  #
  # Prints out a list of the current data services
  #
  def print_data_services()
    @data_services.each_key {|key|
      out = "id: #{key}, description: #{@data_services[key].name}"
      if (!@data_service.nil? && @data_services[key].name == @data_service.name)
        out += " [active]"
      end
      puts out  #hahaha
    }
  end

  #
  # Used to bridge the local db
  #
  def method_missing(method, *args, &block)
    #puts "Attempting to delegate method: #{method}"
    unless @data_service.nil?
      @data_service.send(method, *args, &block)
    end
  end

  def respond_to?(method_name, include_private=false)
    unless @data_service.nil?
      return @data_service.respond_to?(method_name, include_private)
    end

    false
  end

  #
  # Attempt to shutdown the local db process if it exists
  #
  def exit_called
    if @pid
      puts 'Killing db process'
      begin
        Process.kill("TERM", @pid)
      rescue Exception => e
        puts "Unable to kill db process: #{e.message}"
      end
    end
  end

  def get_data_service
    raise 'No registered data_service' unless @data_service
    return @data_service
  end

  #######
  private
  #######

  def setup(opts)
    begin
      db_manager = opts.delete(:db_manager)
      if !db_manager.nil?
        register_data_service(db_manager, true)
        @usable = true
      elsif opts['DatabaseRemoteProcess']
        run_remote_db_process(opts)
        @usable = true
      else
        @error = 'disabled'
      end
    rescue Exception => e
      puts "Unable to initialize a dataservice #{e.message}"
    end
  end

  def validate(data_service)
    raise "Invalid data_service: #{data_service.class}, not of type Metasploit::Framework::DataService" unless data_service.is_a? (Metasploit::Framework::DataService)
    raise 'Cannot register null data service data_service' unless data_service
    raise 'Data Service already exists' if data_service_exist?(data_service)
  end

  def data_service_exist?(data_service)
    @data_services.each_value{|value|
      if (value.name == data_service.name)
        return true
      end
    }

    return false
  end


  def run_remote_db_process(opts)
    # started with no signal to prevent ctrl-c from taking out db
    db_script = File.join( Msf::Config.install_root, "msfdb -ns")
    wait_t = Open3.pipeline_start(db_script)
    @pid = wait_t[0].pid
    puts "Started process with pid #{@pid}"

    endpoint = URI.parse('http://localhost:8080')
    remote_host_data_service = Metasploit::Framework::DataService::RemoteHTTPDataService.new(endpoint)
    register_data_service(remote_host_data_service, true)
  end

end
end
end
end
