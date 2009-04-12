require File.dirname(__FILE__) + '/test_helper'

class TestClient < Test::Unit::TestCase
  
  #Used for mocking HTTP requests
  class Net::HTTP
    class << self
      attr_accessor :response, :request
    end
   
    def request(req)
      self.class.request = req
      self.class.response
    end
  end  
  
  #Mock responses that conform mostly to HTTPResponse's interface
  class MockResponse
    include Net::HTTPHeader
    attr_accessor :code, :body
    def initialize(code,body,headers={})
      self.code = code
      self.body = body
      headers.each do |name, value|
        self[name] = value
      end
    end
  end
  
  #Transport that collects info on requests and responses for testing purposes
  class MockTransport < Grackle::Transport
    attr_accessor :status, :body, :method, :url, :options
    
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
  
  def test_simple_get_request
    client = new_client(200,'{"id":12345,"screen_name":"test_user"}')
    value = client.users.show.json? :screen_name=>'test_user'
    assert_equal(:get,client.transport.method)
    assert_equal('http',client.transport.url.scheme)
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
  
  private
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