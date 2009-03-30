module Grackle
  
  class Response
    attr_accessor :method, :request_uri, :status, :body
    
    def initialize(method,request_uri,status,body)
      self.method = method
      self.request_uri = request_uri
      self.status = status
      self.body = body
    end
  end
  
  class Transport
  
    def get(string_url,options={})
      request(:get,url,options)
    end
    
    def post(string_url,options={})
      request(:post,url,options)
    end
    
    def put(url,options={})
      request(:put,url,options)
    end
    
    def delete(url,options={})
      request(:delete,url,options)
    end
    
    def req_class(method)
      case method
        when :get then Net::HTTP::Get
        when :post then Net::HTTP::Post
        when :put then Net::HTTP::Put
        when :delete then Net::HTTP::Delete
      end
    end
    
    def request(method, string_url, options={})
      params = stringify_params(options[:params])
      if method == :get && params
        string_url << query_string(params)
      end
      url = URI.parse(string_url)
      begin
        if file_param?(options[:params])
          request_multipart(method,url,options)
        else
          request_standard(method,url,options)
        end
      rescue Timeout::Error
        raise "Timeout while #{method}ing #{url.to_s}"
      end
    end
    
    def request_multipart(method, url, options={})
      require 'httpclient' unless defined? HTTPClient
      client = HTTPClient.new
      if options[:username] && options[:password]
        client.set_auth(url.to_s,options.delete(:username),options.delete(:password))
      end
      res = client.request(method,url.to_s,nil,options[:params],options[:headers])
      Response.new(method,url.to_s,res.status,res.content)
    end
    
    def request_standard(method,url,options={})
      Net::HTTP.new(url.host, url.port).start do |http| 
        req = req_class(method).new(url.request_uri)
        add_headers(req,options[:headers])
        add_form_data(req,options[:params])
        add_basic_auth(req,options[:username],options[:password])
        res = http.request(req)
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
    
      def add_basic_auth(req,username,password)
        if username && password
          req.basic_auth(username,password)
        end
      end
  end
end