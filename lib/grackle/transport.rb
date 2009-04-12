module Grackle
  
  class Response #:nodoc:
    attr_accessor :method, :request_uri, :status, :body
    
    def initialize(method,request_uri,status,body)
      self.method = method
      self.request_uri = request_uri
      self.status = status
      self.body = body
    end
  end
  
  class Transport
    
    attr_accessor :debug
  
    CRLF = "\r\n"
    
    def req_class(method)
      case method
        when :get then Net::HTTP::Get
        when :post then Net::HTTP::Post
        when :put then Net::HTTP::Put
        when :delete then Net::HTTP::Delete
      end
    end
    
    # Options are one of
    # - :params - a hash of parameters to be sent with the request. If a File is a parameter value, \
    #             a multipart request will be sent. If a Time is included, .httpdate will be called on it.
    # - :headers - a hash of headers to send with the request
    # - :auth - a hash of authentication parameters for either basic or oauth
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
      Net::HTTP.new(url.host, url.port).start do |http| 
        req = req_class(method).new(url.request_uri)
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
            add_oauth(req,options[:auth])
          end
        end
        dump_request(req) if debug
        res = http.request(req)
        dump_response(res) if debug
        Response.new(method,url.to_s,res.code.to_i,res.body)
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
        if req.request_body_permitted? && params
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
      
      def add_oauth(req,auth)
        options = auth.reject do |key,value|
          [:type,:consumer_key,:consumer_secret,:token,:token_secret].include?(key)
        end
        consumer = OAuth::Consumer.new(auth[:consumer_key],auth[:consumer_secret],options)
        access_token = OAuth::AccessToken.new(consumer,auth[:token],auth[:token_secret])
        consumer.sign!(req,access_token)
      end

      private
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
  end
end