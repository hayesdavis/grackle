module Grackle
  
  class TwitterStruct < OpenStruct
    attr_accessor :id
  end

  class TwitterError < StandardError
    attr_accessor :method, :request_uri, :status, :response_body, :response_object
  
    def initialize(method, request_uri, status, response_body)
      self.method = method
      self.request_uri = request_uri
      self.status = status
      self.response_body = response_body
      super("#{self.method} #{self.request_uri} => #{self.status}: #{self.response_body}")
    end
  end  
  
  class Client
        
    class Request
      attr_accessor :path, :method
      
      def method
        @method ||= :get
      end
      
      def <<(path)
        self.path << path
      end
      
      def path
        @path ||= ''
      end
      
      def path?
        path.length > 0
      end
    end
    
    VALID_METHODS = [:get,:post,:put,:delete]
    VALID_FORMATS = [:json,:xml,:atom,:rss]
    
    REST_API_DOMAIN = 'twitter.com'
    SEARCH_API_DOMAIN = 'search.twitter.com'
    
    attr_accessor :username, :password, :handlers, :default_format, :headers, :ssl, :transport, :request
    
    # Arguments (all are optional):
    #   :username - twitter username to authenticate with
    #   :password - twitter password to authenticate with
    #   :handlers - Hash of formats to Handler instances (e.g. {:json=>CustomJSONHandler.new})
    #   :default_format - Symbol of format to use when no format is specified in an API call (e.g. :json)
    #   :headers - Hash of string keys and values for headers to pass in the HTTP request to twitter
    #   :ssl - true or false to turn SSL on or off. Default is off (i.e. http://)
    def initialize(options={})
      self.transport = Transport.new
      self.username = options.delete(:username)
      self.password = options.delete(:password)
      self.handlers = {:json=>Handlers::JSONHandler.new,:xml=>Handlers::XMLHandler.new,:unknown=>Handlers::StringHandler.new}
      self.handlers.merge!(options[:handlers]||{})
      self.default_format = options[:default_format] || :json 
      self.headers = {'User-Agent'=>'Grackle/1.0'}.merge!(options[:headers]||{})
      self.ssl = options[:ssl] == true
    end
               
    def method_missing(name,*args)
      #Check for HTTP method and apply it to the request. 
      #Can use this for an explict HTTP method
      if http_method_invocation?(name)
        self.request.method = name
        return self
      end
      #If method is a format name, execute using that format
      if format_invocation?(name)
        return call_with_format(name,*args)
      end
      #If method ends in ! or ? use that to determine post or get
      if name.to_s =~ /^(.*)(!|\?)$/
        name = $1.to_sym
        #! is a post, ? is a get
        self.request.method = ($2 == '!' ? :post : :get)          
        if format_invocation?(name)
          return call_with_format(name,*args)
        else
          self.request << "/#{$1}"
          return call_with_format(self.default_format,*args)
        end
      end
      #Else add to the request path
      self.request << "/#{name}"
      self
    end
    
    protected
      def rest_api_domain
        REST_API_DOMAIN
      end
    
      def search_api_domain
        SEARCH_API_DOMAIN
      end

      def call_with_format(format,params={})
        id = params.delete(:id)
        self.request << "/#{id}" if id
        self.request << ".#{format}"
        url = "#{scheme}://#{request_host}#{self.request.path}"
        req_info = self.request
        self.request = nil
        res = transport.request(
          req_info.method,url,:username=>self.username,:password=>self.password,:headers=>headers,:params=>params
        )
        fmt_handler = handler(format) 
        unless res.status == 200
          handle_error_response(res,fmt_handler)
        else
          fmt_handler.decode_response(res.body)
        end
      end
      
      def request
        @request ||= Request.new
      end
      
    private
      def handler(format)
        handlers[format] || handlers[:unknown]
      end
      
      def handle_error_response(res,handler)
        err = TwitterError.new(res.method,res.request_uri,res.status,res.body)
        err.response_object = handler.decode_response(err.response_body)
        raise err        
      end
      
      def http_method_invocation?(name)
        !self.request.path? && VALID_METHODS.include?(name)
      end
      
      def format_invocation?(name)
        self.request.path? && VALID_FORMATS.include?(name)
      end
            
      def request_host
        self.request.path =~ /^\/search/ ? search_api_domain : rest_api_domain
      end
    
      def scheme
        self.ssl ? 'https' :'http'
      end
    
  end
end