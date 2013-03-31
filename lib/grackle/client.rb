module Grackle
  
  #Returned by methods which retrieve data from the API
  class TwitterStruct < OpenStruct
    attr_accessor :id
  end

  #Raised by methods which call the API if a non-200 response status is received 
  class TwitterError < StandardError
    attr_accessor :method, :request_uri, :status, :response_body, :response_object
  
    def initialize(method, request_uri, status, response_body, msg=nil)
      self.method = method
      self.request_uri = request_uri
      self.status = status
      self.response_body = response_body
      super(msg||"#{self.method} #{self.request_uri} => #{self.status}: #{self.response_body}")
    end
  end  
  
  # The Client is the public interface to Grackle. You build Twitter API calls using method chains. See the README for details 
  # and new for information on valid options.
  #
  # ==Authentication
  # Twitter is migrating to OAuth as the preferred mechanism for authentication (over HTTP basic auth). Grackle supports both methods.
  # Typically you will supply Grackle with authentication information at the time you create your Grackle::Client via the :auth parameter.
  # ===Basic Auth
  #   client = Grackle.Client.new(:auth=>{:type=>:basic,:username=>'twitteruser',:password=>'secret'})
  # Please note that the original way of specifying basic authentication still works but is deprecated
  #   client = Grackle.Client.new(:username=>'twitteruser',:password=>'secret') #deprecated
  #
  # ===OAuth
  # OAuth is a relatively complex topic. For more information on OAuth applications see the official OAuth site at http://oauth.net and the 
  # OAuth specification at http://oauth.net/core/1.0. For authentication using OAuth, you will need do the following:
  # - Acquire a key and token for your application ("Consumer" in OAuth terms) from Twitter. Learn more here:  http://apiwiki.twitter.com/OAuth-FAQ
  # - Acquire an access token and token secret for the user that will be using OAuth to authenticate into Twitter
  # The process of acquiring the access token and token secret are outside the scope of Grackle and will need to be coded on a per-application 
  # basis. Grackle comes into play once you've acquired all of the above pieces of information. To create a Grackle::Client that uses OAuth once 
  # you've got all the necessary tokens and keys:
  #   client = Grackle::Client.new(:auth=>{
  #     :type=>:oauth,
  #     :consumer_key=>'SOMECONSUMERKEYFROMTWITTER, :consumer_secret=>'SOMECONSUMERTOKENFROMTWITTER',
  #     :token=>'ACCESSTOKENACQUIREDONUSERSBEHALF', :token_secret=>'SUPERSECRETACCESSTOKENSECRET'
  #   }) 
  class Client
    
    class Request #:nodoc:
      attr_accessor :client, :path, :method, :api, :ssl, :params
      
      def initialize(client,api=:rest,ssl=true)
        self.client = client
        self.api = api
        self.ssl = ssl
        self.path = ''
      end
      
      def <<(path)
        self.path << path
      end
      
      def path?
        path.length > 0
      end
    
      def url
        "#{scheme}://#{host}#{path}"
      end
         
      def host
        client.api_hosts[api]
      end
    
      def scheme
        ssl ? 'https' :'http'
      end
      
      def params
        @params ||= {}
      end
    end
    
    VALID_FORMATS     = [:json,:xml,:atom,:rss]
    VALID_HTTP_CODES  = [200]

    # Contains the mapping of API name symbols to actual host (and path) 
    # prefixes to use with requests. You can add your own to this hash and 
    # refer to it wherever Grackle::Client uses an API symbol. You may wish 
    # to do this when Twitter introduces API versions greater than 1.
    TWITTER_API_HOSTS = {
      :v1=>'api.twitter.com/1', :v1_1=>'api.twitter.com/1.1',
      :search=>'search.twitter.com',
      :upload=>'upload.twitter.com/1'
    }
    TWITTER_API_HOSTS[:rest] = TWITTER_API_HOSTS[:v1]
    DEFAULT_API_HOST = :v1_1

    # Contains the response headers from twitter
    DEFAULT_RESPONSE_HEADERS = [
      # These are API 1 rate limit header names
      'x-ratelimit-limit',
      'x-ratelimit-remaining',
      'x-ratelimit-reset',
      # These are API 1.1 rate limit header names
      'x-rate-limit-limit',
      'x-rate-limit-remaining',
      'x-rate-limit-reset'
    ]

    #Basic OAuth information needed to communicate with Twitter
    TWITTER_OAUTH_SPEC = {
      :request_token_path=>'/oauth/request_token',
      :access_token_path=>'/oauth/access_token',
      :authorize_path=>'/oauth/authorize'
    }
    
    attr_accessor :auth, :handlers, :default_format, :headers, :ssl, :api, 
      :transport, :request, :api_hosts, :timeout, :auto_append_ids,
      :auto_append_format, :response_headers, :response, :valid_http_codes
    
    # Arguments (all are optional):
    # - :username           - Twitter username to authenticate with (deprecated in favor of :auth arg)
    # - :password           - Twitter password to authenticate with (deprecated in favor of :auth arg)
    # - :handlers           - Hash of formats to Handler instances (e.g. {:json=>CustomJSONHandler.new})
    # - :default_format     - Symbol of format to use when no format is specified in an API call (e.g. :json, :xml)
    # - :headers            - Hash of string keys and values for headers to pass in the HTTP request to twitter
    # - :ssl                - true or false to turn SSL on or off. Default is off (i.e. http://)
    # - :api                - one of :rest, :search, :v1 or :v1_1. :v1_1 is the default. :rest and :search are now deprecated
    # - :auth               - Hash of authentication type and credentials. Must have :type key with value one of :basic or :oauth
    #   - :type=>:oauth     - Include :consumer_key, :consumer_secret, :token and :token_secret keys
    #   - :type=>:basic     - DEPRECATED. Include :username and :password keys
    # - :auto_append_format - true or false to include format in URI (e.g. /test.json). Default is true
    # - :response_headers   - array of headers to return from the response
    # - :valid_http_codes   - array of HTTP codes to consider valid (non-error)
    def initialize(options={})
      self.transport = Transport.new
      self.handlers = {:json=>Handlers::JSONHandler.new,:xml=>Handlers::XMLHandler.new,:unknown=>Handlers::StringHandler.new}
      self.handlers.merge!(options[:handlers]||{})
      self.default_format = options[:default_format] || :json
      self.auto_append_format = options[:auto_append_format] == false ? false : true
      self.headers = {"User-Agent"=>"Grackle/#{Grackle::VERSION}"}.merge!(options[:headers]||{})
      self.ssl = options[:ssl] == true
      self.api = options[:api] || DEFAULT_API_HOST
      self.api_hosts = TWITTER_API_HOSTS.clone
      self.timeout = options[:timeout] || 60
      self.auto_append_ids = options[:auto_append_ids] == false ? false : true
      self.auth = {}
      self.response_headers = options[:response_headers] || DEFAULT_RESPONSE_HEADERS.clone
      self.valid_http_codes = options[:valid_http_codes] || VALID_HTTP_CODES.clone
      if options.has_key?(:username) || options.has_key?(:password)
        # DEPRECATED: Use basic auth if :username and :password args are passed in
        self.auth.merge!({:type=>:basic,:username=>options[:username],:password=>options[:password]})
      end
      #Handle auth mechanism that permits basic or oauth
      if options.has_key?(:auth)
        self.auth = options[:auth]
        if auth[:type] == :oauth
          self.auth = TWITTER_OAUTH_SPEC.merge(auth)
        end
      end
    end

    def method_missing(name,*args,&block)
      if block_given?
        return request_with_http_method_block(name,&block)
      end
      append(name,*args)
    end
    
    # Used to toggle APIs for a particular request without setting the Client's default API
    #   client[:rest].users.show.hayesdavis?
    def [](api_name)
      request.api = api_name
      self
    end
    
    #Clears any pending request built up by chained methods but not executed
    def clear
      self.request = nil
    end
    
    #Deprecated in favor of using the auth attribute.
    def username
      if auth[:type] == :basic
        auth[:username]
      end
    end
    
    #Deprecated in favor of using the auth attribute.    
    def username=(value)
      unless auth[:type] == :basic
        auth[:type] = :basic        
      end
      auth[:username] = value
    end
    
    #Deprecated in favor of using the auth attribute.    
    def password
      if auth[:type] == :basic
        auth[:password]
      end
    end
    
    #Deprecated in favor of using the auth attribute.    
    def password=(value)
      unless auth[:type] == :basic
        auth[:type] = :basic
      end
      auth[:password] = value
    end
    
    def append(name,*args)
      name = name.to_s.to_sym
      #The args will be a hash, store them if they're specified
      self.request.params = args.first
      #If method is a format name, execute using that format
      if format_invocation?(name)
        return call_with_format(name)
      end
      #If method ends in ! or ? use that to determine post or get
      if name.to_s =~ /^(.*)(!|\?)$/
        name = $1.to_sym
        #! is a post, ? is a get - only set this if the method hasn't been set
        self.request.method ||= ($2 == '!' ? :post : :get)          
        if format_invocation?(name)
          return call_with_format(name)
        else
          self.request << "/#{$1}"
          return call_with_format(self.default_format)
        end
      end
      #Else add to the request path
      self.request << "/#{name}"
      self
    end
    
    alias_method :_, :append
    
    protected
      def call_with_format(format)
        if auto_append_ids
          id = request.params.delete(:id)
          request << "/#{id}" if id
        end
        if auto_append_format
          request << ".#{format}"
        end
        res = send_request
        process_response(format,res)
      ensure
        clear
      end
      
      def send_request
        begin
          http_method = (
            request.params.delete(:__method) or request.method or :get
          )
          @response = transport.request(
            http_method, request.url,
            :auth=>auth,:headers=>headers,
            :params=>request.params,:timeout=>timeout,
            :response_headers=>response_headers
          )
        rescue => e
          puts e
          raise TwitterError.new(request.method,request.url,nil,nil,"Unexpected failure making request: #{e}")
        end        
      end
      
      def process_response(format,res)
        fmt_handler = handler(format)        
        begin
          unless self.valid_http_codes.include?(res.status)
            handle_error_response(res,fmt_handler)
          else
            fmt_handler.decode_response(res.body)
          end
        rescue TwitterError => e
          raise e
        rescue => e
          raise TwitterError.new(res.method,res.request_uri,res.status,res.body,"Unable to decode response: #{e}")
        end
      end
      
      def request
        @request ||= Request.new(self,api,ssl)
      end
      
      def handler(format)
        handlers[format] || handlers[:unknown]
      end
      
      def handle_error_response(res,handler)
        err = TwitterError.new(res.method,res.request_uri,res.status,res.body)
        err.response_object = handler.decode_response(err.response_body)
        raise err        
      end
      
      def format_invocation?(name)
        self.request.path? && VALID_FORMATS.include?(name)
      end
      
      def pending_request?
        !@request.nil?
      end

      def request_with_http_method_block(method,&block)
        request.method = method
        response = instance_eval(&block)
        if pending_request?
          call_with_format(self.default_format)
        else
          response
        end
      end
  end
end
