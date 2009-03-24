module Grackle
  
  class TwitterStruct < OpenStruct
    attr_accessor :id
  end

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
  class Client
        
    class Request
      attr_accessor :path, :method, :api, :ssl
      
      def initialize(api=:rest,ssl=true)
        self.api = api
        self.ssl = ssl
        self.method = :get
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
        APIS[api]
      end
    
      def scheme
        ssl ? 'https' :'http'
      end
    end
    
    VALID_METHODS = [:get,:post,:put,:delete]
    VALID_FORMATS = [:json,:xml,:atom,:rss]

    APIS = {:rest=>'twitter.com',:search=>'search.twitter.com'}
    
    attr_accessor :username, :password, :handlers, :default_format, :headers, :ssl, :api, :transport, :request 
    
    # Arguments (all are optional):
    # - :username       - twitter username to authenticate with
    # - :password       - twitter password to authenticate with
    # - :handlers       - Hash of formats to Handler instances (e.g. {:json=>CustomJSONHandler.new})
    # - :default_format - Symbol of format to use when no format is specified in an API call (e.g. :json, :xml)
    # - :headers        - Hash of string keys and values for headers to pass in the HTTP request to twitter
    # - :ssl            - true or false to turn SSL on or off. Default is off (i.e. http://)
    # - :api            - one of :rest or :search
    def initialize(options={})
      self.transport = Transport.new
      self.username = options.delete(:username)
      self.password = options.delete(:password)
      self.handlers = {:json=>Handlers::JSONHandler.new,:xml=>Handlers::XMLHandler.new,:unknown=>Handlers::StringHandler.new}
      self.handlers.merge!(options[:handlers]||{})
      self.default_format = options[:default_format] || :json 
      self.headers = {'User-Agent'=>'Grackle/1.0'}.merge!(options[:headers]||{})
      self.ssl = options[:ssl] == true
      self.api = options[:api] || :rest
    end
               
    def method_missing(name,*args)
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
    
    protected
      def call_with_format(format,params={})
        id = params.delete(:id)
        request << "/#{id}" if id
        request << ".#{format}"
        res = send_request(params)
        process_response(format,res)
      ensure
        clear
      end
      
      def send_request(params)
        begin
          transport.request(
            request.method,request.url,:username=>self.username,:password=>self.password,:headers=>headers,:params=>params
          )
        rescue => e
          puts e
          raise TwitterError.new(request.method,request.url,nil,nil,"Unexpected failure making request: #{e}")
        end        
      end
      
      def process_response(format,res)
        fmt_handler = handler(format)        
        begin
          unless res.status == 200
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
        @request ||= Request.new(api,ssl)
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
  end
end