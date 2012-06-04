module Grackle

  class Headers #:nodoc:
    include Enumerable

    def initialize
      @data = {}
    end

    def [](name)
      res = @data[name.downcase.to_sym]
      res ? res.join(",") : nil
    end

    def []=(name,value)
      @data[name.downcase.to_sym] = [value]
    end

    def add(name,value)
      res = (@data[name.downcase.to_sym] ||= [])
      res << value
    end

    def add_all(name,values)
      res = (@data[name.downcase.to_sym] ||= [])
      res.push(*values)
    end

    def each
      @data.each do |name,value|
        yield(name.to_s,value.join(","))
      end
    end

    def size
      @data.size
    end
  end

  class Response #:nodoc:
    attr_accessor :method, :request_uri, :status, :body, :headers
    
    def initialize(method,request_uri,status,body,headers)
      self.method = method
      self.request_uri = request_uri
      self.status = status
      self.headers = headers
      self.body = body
    end
  end
  
  class Transport
    
    attr_accessor :debug, :proxy
  
    CRLF = "\r\n"
    DEFAULT_REDIRECT_LIMIT = 5
    
    class << self
      attr_accessor :ca_cert_file
    end
    
    def req_class(method)
      Net::HTTP.const_get(method.to_s.capitalize)
    end
    
    # Options are one of
    # - :params - a hash of parameters to be sent with the request. If a File is a parameter value, \
    #             a multipart request will be sent. If a Time is included, .httpdate will be called on it.
    # - :headers - a hash of headers to send with the request
    # - :auth - a hash of authentication parameters for either basic or oauth
    # - :timeout - timeout for the http request in seconds
    # - :response_headers - a list of headers to return with the response
    def request(method, string_url, options={})
      params = stringify_params(options[:params])
      if method == :get && params
        string_url << query_string(params)
      end
      url = URI.parse(string_url)
      begin
        execute_request(method,url,options)
      rescue Timeout::Error
        raise "Timeout while #{method}ing #{url.to_s}"
      end
    end
    
    def execute_request(method,url,options={})
      conn = http_class.new(url.host, url.port)
      conn.use_ssl = (url.scheme == 'https')
      if conn.use_ssl?
        configure_ssl(conn)
      end
      conn.start do |http| 
        req = req_class(method).new(url.request_uri)
        http.read_timeout = options[:timeout]
        add_headers(req,options[:headers])
        if file_param?(options[:params])
          add_multipart_data(req,options[:params])
        else
          add_form_data(req,options[:params])
        end
        if options.has_key? :auth
          if options[:auth][:type] == :basic
            add_basic_auth(req,options[:auth])
          elsif options[:auth][:type] == :oauth
            add_oauth(http,req,options[:auth])
          end
        end
        dump_request(req) if debug
        res = http.request(req)
        dump_response(res) if debug
        redirect_limit = options[:redirect_limit] || DEFAULT_REDIRECT_LIMIT
        if res.code.to_s =~ /^3\d\d$/ && redirect_limit > 0 && res['location']
          execute_request(method,URI.parse(res['location']),options.merge(:redirect_limit=>redirect_limit-1))
        else
          headers = filter_headers(options[:response_headers],res)
          Response.new(method,url.to_s,res.code.to_i,res.body,headers)
        end
      end
    end

    def query_string(params)
      query = case params
        when Hash then params.map{|key,value| url_encode_param(key,value) }.join("&")
        else url_encode(params.to_s)
      end
      if !(query == nil || query.length == 0) && query[0,1] != '?'
        query = "?#{query}"
      end
      query
    end      
  
    private
      def stringify_params(params)
        return nil unless params
        params.inject({}) do |h, pair|
          key, value = pair
          if value.respond_to? :httpdate
            value = value.httpdate
          end
          h[key] = value
          h
        end
      end
      
      def file_param?(params)
        return false unless params
        params.any? {|key,value| value.respond_to? :read }
      end
      
      def url_encode(value)
        require 'cgi' unless defined?(CGI) && defined?(CGI::escape)
        CGI.escape(value.to_s)
      end
      
      def url_encode_param(key,value)
        "#{url_encode(key)}=#{url_encode(value)}"
      end
      
      def add_headers(req,headers)
        if headers
          headers.each do |header, value|
            req[header] = value
          end
        end        
      end
    
      def add_form_data(req,params)
        if request_body_permitted?(req) && params
          req.set_form_data(params)
        end
      end
    
      def add_multipart_data(req,params)
        boundary = Time.now.to_i.to_s(16)
        req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        body = ""
        params.each do |key,value|
          esc_key = url_encode(key)
          body << "--#{boundary}#{CRLF}"
          if value.respond_to?(:read)
            mime_type = MIME::Types.type_for(value.path)[0] || MIME::Types["application/octet-stream"][0]
            body << "Content-Disposition: form-data; name=\"#{esc_key}\"; filename=\"#{File.basename(value.path)}\"#{CRLF}"
            body << "Content-Type: #{mime_type.simplified}#{CRLF*2}"
            body << value.read
          else
            body << "Content-Disposition: form-data; name=\"#{esc_key}\"#{CRLF*2}#{value}"
          end
          body << CRLF
        end
        body << "--#{boundary}--#{CRLF*2}"
        req.body = body
        req["Content-Length"] = req.body.size
      end
    
      def add_basic_auth(req,auth)
        username = auth[:username]
        password = auth[:password]
        if username && password
          req.basic_auth(username,password)
        end
      end
      
      def add_oauth(conn,req,auth)
        options = auth.reject do |key,value|
          [:type,:consumer_key,:consumer_secret,:token,:token_secret].include?(key)
        end
        unless options.has_key?(:site)
          options[:site] = oauth_site(conn,req)
        end
        consumer = OAuth::Consumer.new(auth[:consumer_key],auth[:consumer_secret],options)
        access_token = OAuth::AccessToken.new(consumer,auth[:token],auth[:token_secret])
        consumer.sign!(req,access_token)
      end

      def oauth_site(conn,req)
        site = "#{(conn.use_ssl? ? "https" : "http")}://#{conn.address}"
        if (conn.use_ssl? && conn.port != 443) || (!conn.use_ssl? && conn.port != 80) 
          site << ":#{conn.port}"
        end
        site
      end
      
      def dump_request(req)
        puts "Sending Request"
        puts"#{req.method} #{req.path}"
        dump_headers(req)
      end
    
      def dump_response(res)
        puts "Received Response"
        dump_headers(res)
        puts res.body
      end
    
      def dump_headers(msg)
        msg.each_header do |key, value|
          puts "\t#{key}=#{value}"
        end
      end

      def filter_headers(headers, res)
        filtered = Headers.new
        headers.each do |h|
          filtered.add(h, res[h])
        end
        filtered
      end

      def http_class
        if proxy
          if proxy.kind_of?(Proc)
            proxy.call(self)
          else
            proxy
          end
        else
          Net::HTTP
        end
      end

      def configure_ssl(conn)
        if self.class.ca_cert_file
          conn.verify_mode = OpenSSL::SSL::VERIFY_PEER
          conn.ca_file = self.class.ca_cert_file
        else
          # Turn off SSL verification which gets rid of warning in 1.8.x and 
          # an error in 1.9.x.
          conn.verify_mode = OpenSSL::SSL::VERIFY_NONE
          unless @ssl_warning_shown
            puts <<-EOS
Warning: SSL Verification is not being performed. While your communication is 
being encrypted, the identity of the other party is not being confirmed nor the 
SSL certificate verified. It's recommended that you specify a file containing 
root SSL certificates like so:
 
Grackle::Transport.ca_cert_file = "path/to/cacerts.pem"
  
You can download this kind of file from the maintainers of cURL:
http://curl.haxx.se/ca/cacert.pem
  
EOS
            @ssl_warning_shown = true
          end
        end
      end

      # Methods like Twitter's DELETE list membership expect that the user id 
      # will be form encoded like a POST request in the body. Net::HTTP seems 
      # to think that DELETEs can't have body parameters so we have to work 
      # around that.
      def request_body_permitted?(req)
        req.request_body_permitted? || req.kind_of?(Net::HTTP::Delete)
      end
  end
end
