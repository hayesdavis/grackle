require File.dirname(__FILE__) + '/test_helper'

class HandlersTest < Test::Unit::TestCase
  
  def test_string_handler_echoes
    sh = Grackle::Handlers::StringHandler.new
    body = "This is some text"
    assert_equal(body,sh.decode_response(body),"String handler should just echo response body")
  end
  
  def test_xml_handler_parses_text_only_nodes_as_attributes
    h = Grackle::Handlers::XMLHandler.new
    body = "<user><id>12345</id><screen_name>User1</screen_name></user>"
    value = h.decode_response(body)
    assert_equal(12345,value.id,"Id element should be treated as an attribute and be returned as a Fixnum")
    assert_equal("User1",value.screen_name,"screen_name element should be treated as an attribute")
  end
  
  def test_xml_handler_parses_nested_elements_with_children_as_nested_objects
    h = Grackle::Handlers::XMLHandler.new
    body = "<user><id>12345</id><screen_name>User1</screen_name><status><id>9876</id><text>this is a status</text></status></user>"
    value = h.decode_response(body)
    assert_not_nil(value.status,"status element should be turned into an object")
    assert_equal(9876,value.status.id,"status element should have id")
    assert_equal("this is a status",value.status.text,"status element should have text")
  end
  
  def test_xml_handler_parses_elements_with_type_array_as_arrays
    h  = Grackle::Handlers::XMLHandler.new
    body = "<some_ids type=\"array\">"
    1.upto(10) do |i|
      body << "<id>#{i}</id>"
    end
    body << "</some_ids>"
    value = h.decode_response(body)    
    assert_equal(Array,value.class,"Root parsed object should be an array")
    assert_equal(10,value.length,"Parsed array should have correct length")
    0.upto(9) do |i|
      assert_equal(i+1,value[i],"Parsed array should contain #{i+1} at index #{i}")
    end
  end
  
  def test_xml_handler_parses_certain_elements_as_arrays
    h  = Grackle::Handlers::XMLHandler.new
    special_twitter_elements = ['ids','statuses','users']
    special_twitter_elements.each do |name|
      body = "<#{name}>"
      1.upto(10) do |i|
        body << "<complex_value><id>#{i}</id><profile>This is profile #{i}</profile></complex_value>"
      end
      body << "</#{name}>"
      value = h.decode_response(body)    
      assert_equal(Array,value.class,"Root parsed object should be an array")
      assert_equal(10,value.length,"Parsed array should have correct length")
      0.upto(9) do |i|
        assert_equal(i+1,value[i].id,"Parsed array should contain id #{i+1} at index #{i}")
        assert_equal("This is profile #{i+1}",value[i].profile,"Parsed array should contain profile 'This is profile #{i+1}' at index #{i}")
      end
    end
  end
  
  def test_json_handler_parses_basic_attributes
    h = Grackle::Handlers::JSONHandler.new
    body = '{"id":12345,"screen_name":"User1"}'
    value = h.decode_response(body)
    assert_equal(12345,value.id,"Id element should be treated as an attribute and be returned as a Fixnum")
    assert_equal("User1",value.screen_name,"screen_name element should be treated as an attribute")    
  end
  
  def test_json_handler_parses_complex_attributes
    h = Grackle::Handlers::JSONHandler.new
    body = '{"id":12345,"screen_name":"User1","statuses":['
    1.upto(10) do |i|
      user_id = i+5000
      body << ',' unless i == 1
      body << %Q{{"id":#{i},"text":"Status from user #{user_id}", "user":{"id":#{user_id},"screen_name":"User #{user_id}"}}}
    end
    body << ']}'
    value = h.decode_response(body)
    assert_equal(12345,value.id,"Id element should be treated as an attribute and be returned as a Fixnum")
    assert_equal("User1",value.screen_name,"screen_name element should be treated as an attribute")
    assert_equal(Array,value.statuses.class,"statuses attribute should be an array")
    1.upto(10) do |i|
      assert_equal(i,value.statuses[i-1].id,"array should contain status with id #{i} at index #{i-1}")
      assert_equal(i+5000,value.statuses[i-1].user.id,"status at index #{i-1} should contain user with id #{i+5000}")
    end
  end
  
end