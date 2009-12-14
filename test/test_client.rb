require File.dirname(__FILE__) + '/test_helper'

class TestClient < Test::Unit::TestCase
  
  #Used for mocking HTTP requests
  class Net::HTTP
    class << self
      attr_accessor :response, :request, :last_instance, :responder
    end
    
    def connect
      # This needs to be overridden so SSL requests can be mocked
    end
   
    def request(req)
      self.class.last_instance = self
      if self.class.responder
        self.class.responder.call(self,req)        
      else
        self.class.request = req
        self.class.response
      end
    end
  end  
  
  #Mock responses that conform to HTTPResponse's interface
  class MockResponse < Net::HTTPResponse
    #include Net::HTTPHeader
    attr_accessor :code, :body
    def initialize(code,body,headers={})
      super
      self.code = code
      self.body = body
      headers.each do |name, value|
        self[name] = value
      end
    end
  end
  
  #Transport that collects info on requests and responses for testing purposes
  class MockTransport < Grackle::Transport
    attr_accessor :status, :body, :method, :url, :options, :timeout
    
    def initialize(status,body,headers={})
      Net::HTTP.response = MockResponse.new(status,body,headers)
    end
    
    def request(method, string_url, options)
      self.method = method
      self.url = URI.parse(string_url)
      self.options = options
      super(method,string_url,options)
    end
  end
  
  class TestHandler
    attr_accessor :decode_value
    
    def initialize(value)
      self.decode_value = value
    end
    
    def decode_response(body)
      decode_value  
    end
  end
  
  def test_redirects
    redirects = 2 #Check that we can follow 2 redirects before getting to original request
    req_count = 0
    responder = Proc.new do |inst, req|
      req_count += 1
      #Store the original request
      if req_count == 1
        inst.class.request = req 
      else
        assert_equal("/somewhere_else#{req_count-1}.json",req.path)
      end
      if req_count <= redirects
        MockResponse.new(302,"You are being redirected",'location'=>"http://twitter.com/somewhere_else#{req_count}.json")
      else
        inst.class.response
      end
    end
    with_http_responder(responder) do
      test_simple_get_request
    end
    assert_equal(redirects+1,req_count)
  end
  
  def test_timeouts
    client = new_client(200,'{"id":12345,"screen_name":"test_user"}')
    assert_equal(60, client.timeout)
    client.timeout = 30
    assert_equal(30, client.timeout)
  end
  
  def test_simple_get_request
    client = new_client(200,'{"id":12345,"screen_name":"test_user"}')
    value = client.users.show.json? :screen_name=>'test_user'
    assert_equal(:get,client.transport.method)
    assert_equal('http',client.transport.url.scheme)
    assert(!Net::HTTP.last_instance.use_ssl?,'Net::HTTP instance should not be set to use SSL')
    assert_equal('twitter.com',client.transport.url.host)
    assert_equal('/users/show.json',client.transport.url.path)
    assert_equal('test_user',client.transport.options[:params][:screen_name])
    assert_equal('screen_name=test_user',Net::HTTP.request.path.split(/\?/)[1])
    assert_equal(12345,value.id)
  end
  
  def test_simple_post_request_with_basic_auth
    client = Grackle::Client.new(:auth=>{:type=>:basic,:username=>'fake_user',:password=>'fake_pass'})
    test_simple_post(client) do
      assert_match(/Basic/i,Net::HTTP.request['Authorization'],"Request should include Authorization header for basic auth")
    end
  end
  
  def test_simple_post_request_with_oauth
    client = Grackle::Client.new(:auth=>{:type=>:oauth,:consumer_key=>'12345',:consumer_secret=>'abc',:token=>'wxyz',:token_secret=>'98765'})
    test_simple_post(client) do
      auth = Net::HTTP.request['Authorization']
      assert_match(/OAuth/i,auth,"Request should include Authorization header for OAuth")
      assert_match(/oauth_consumer_key="12345"/,auth,"Auth header should include consumer key")
      assert_match(/oauth_token="wxyz"/,auth,"Auth header should include token")
      assert_match(/oauth_signature_method="HMAC-SHA1"/,auth,"Auth header should include HMAC-SHA1 signature method as that's what Twitter supports")
    end
  end
  
  def test_ssl
    client = new_client(200,'[{"id":1,"text":"test 1"}]',:ssl=>true)
    client.statuses.public_timeline?
    assert_equal("https",client.transport.url.scheme)
    assert(Net::HTTP.last_instance.use_ssl?,'Net::HTTP instance should be set to use SSL')
  end
  
  def test_ssl_with_ca_cert_file
    MockTransport.ca_cert_file = "some_ca_certs.pem"
    client = new_client(200,'[{"id":1,"text":"test 1"}]',:ssl=>true)
    client.statuses.public_timeline?
    assert_equal(OpenSSL::SSL::VERIFY_PEER,Net::HTTP.last_instance.verify_mode,'Net::HTTP instance should use OpenSSL::SSL::VERIFY_PEER mode')
    assert_equal(MockTransport.ca_cert_file,Net::HTTP.last_instance.ca_file,'Net::HTTP instance should have cert file set')
  end
  
  def test_default_format
    client = new_client(200,'[{"id":1,"text":"test 1"}]',:default_format=>:json)
    client.statuses.public_timeline?
    assert_match(/\.json$/,client.transport.url.path)
    
    client = new_client(200,'<statuses type="array"><status><id>1</id><text>test 1</text></status></statuses>',:default_format=>:xml)
    client.statuses.public_timeline?
    assert_match(/\.xml$/,client.transport.url.path)
  end
  
  def test_api
    client = new_client(200,'[{"id":1,"text":"test 1"}]',:api=>:search)
    client.search? :q=>'test'
    assert_equal('search.twitter.com',client.transport.url.host)

    client[:rest].users.show.some_user?
    assert_equal('twitter.com',client.transport.url.host)

    client.api = :search
    client.trends?
    assert_equal('search.twitter.com',client.transport.url.host)
    
    client.api = :v1
    client.search? :q=>'test'
    assert_equal('api.twitter.com',client.transport.url.host)
    assert_match(%r{^/1/search},client.transport.url.path)

    client.api = :rest
    client[:v1].users.show.some_user?
    assert_equal('api.twitter.com',client.transport.url.host)
    assert_match(%r{^/1/users/show/some_user},client.transport.url.path)
  end
  
  def test_headers
    client = new_client(200,'[{"id":1,"text":"test 1"}]',:headers=>{'User-Agent'=>'TestAgent/1.0','X-Test-Header'=>'Header Value'})
    client.statuses.public_timeline?
    assert_equal('TestAgent/1.0',Net::HTTP.request['User-Agent'],"Custom User-Agent header should have been set")
    assert_equal('Header Value',Net::HTTP.request['X-Test-Header'],"Custom X-Test-Header header should have been set")
  end
  
  def test_custom_handlers
    client = new_client(200,'[{"id":1,"text":"test 1"}]',:handlers=>{:json=>TestHandler.new(42)})
    value = client.statuses.public_timeline.json?
    assert_equal(42,value)
  end
  
  def test_clear
    client = new_client(200,'[{"id":1,"text":"test 1"}]')
    client.some.url.that.does.not.exist
    assert_equal('/some/url/that/does/not/exist',client.send(:request).path,"An unexecuted path should be build up")
    client.clear
    assert_equal('',client.send(:request).path,"The path shoudl be cleared")
  end
  
  def test_file_param_triggers_multipart_encoding
    client = new_client(200,'[{"id":1,"text":"test 1"}]')
    client.account.update_profile_image! :image=>File.new(__FILE__)    
    assert_match(/multipart\/form-data/,Net::HTTP.request['Content-Type'])
  end
  
  def test_time_param_is_http_encoded_and_escaped
    client = new_client(200,'[{"id":1,"text":"test 1"}]')
    time = Time.now-60*60
    client.statuses.public_timeline? :since=>time  
    assert_equal("/statuses/public_timeline.json?since=#{CGI::escape(time.httpdate)}",Net::HTTP.request.path)
  end

  def test_simple_http_method_block
    client = new_client(200,'[{"id":1,"text":"test 1"}]')
    client.delete { direct_messages.destroy :id=>1, :other=>'value' }
    assert_equal(:delete,client.transport.method, "delete block should use delete method")
    assert_equal("/direct_messages/destroy/1.json",Net::HTTP.request.path)
    assert_equal('value',client.transport.options[:params][:other])
    
    client = new_client(200,'{"id":54321,"screen_name":"test_user"}')
    value = client.get { users.show.json? :screen_name=>'test_user' }
    assert_equal(:get,client.transport.method)
    assert_equal('http',client.transport.url.scheme)
    assert(!Net::HTTP.last_instance.use_ssl?,'Net::HTTP instance should not be set to use SSL')
    assert_equal('twitter.com',client.transport.url.host)
    assert_equal('/users/show.json',client.transport.url.path)
    assert_equal('test_user',client.transport.options[:params][:screen_name])
    assert_equal('screen_name=test_user',Net::HTTP.request.path.split(/\?/)[1])
    assert_equal(54321,value.id)    
  end
  
  def test_http_method_blocks_choose_right_method
    client = new_client(200,'[{"id":1,"text":"test 1"}]')
    client.get { search :q=>'test' }
    assert_equal(:get,client.transport.method, "Get block should choose get method")
    client.delete { direct_messages.destroy :id=>1 }
    assert_equal(:delete,client.transport.method, "Delete block should choose delete method")
    client.post { direct_messages.destroy :id=>1 }
    assert_equal(:post,client.transport.method, "Post block should choose post method")
    client.put { direct_messages :id=>1 }
    assert_equal(:put,client.transport.method, "Put block should choose put method")
  end
  
  def test_http_method_selection_precedence
    client = new_client(200,'[{"id":1,"text":"test 1"}]')
    client.get { search! :q=>'test' }
    assert_equal(:get,client.transport.method, "Get block should override method even if post bang is used")
    client.delete { search? :q=>'test', :__method=>:post }
    assert_equal(:post,client.transport.method, ":__method=>:post should override block setting and method suffix")
  end
  
  def test_underscore_method_works_with_numbers
    client = new_client(200,'{"id":12345,"screen_name":"test_user"}')
    value = client.users.show._(12345).json?
    assert_equal(:get,client.transport.method)
    assert_equal('http',client.transport.url.scheme)
    assert(!Net::HTTP.last_instance.use_ssl?,'Net::HTTP instance should not be set to use SSL')
    assert_equal('twitter.com',client.transport.url.host)
    assert_equal('/users/show/12345.json',client.transport.url.path)
    assert_equal(12345,value.id)
  end
  
  private
    def with_http_responder(responder)
      Net::HTTP.responder = responder
      yield
    ensure
      Net::HTTP.responder = nil
    end
    
    def new_client(response_status, response_body, client_opts={})
      client = Grackle::Client.new(client_opts)
      client.transport = MockTransport.new(response_status,response_body)
      client
    end
    
    def test_simple_post(client)
      client.transport = MockTransport.new(200,'{"id":12345,"text":"test status"}')
      value = client.statuses.update! :status=>'test status'
      assert_equal(:post,client.transport.method,"Expected post request")
      assert_equal('http',client.transport.url.scheme,"Expected scheme to be http")
      assert_equal('twitter.com',client.transport.url.host,"Expected request to be against twitter.com")
      assert_equal('/statuses/update.json',client.transport.url.path)
      assert_match(/status=test%20status/,Net::HTTP.request.body,"Parameters should be form encoded")
      assert_equal(12345,value.id)
      yield(client) if block_given?
    end
  
end