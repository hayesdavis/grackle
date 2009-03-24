module Grackle
  
  # This module contain handlers that know how to take a response body 
  # from Twitter and turn it into a TwitterStruct return value. Handlers are 
  # used by the Client to give back return values from API calls. A handler
  # is intended to provide a +decode_response+ method which accepts the response body 
  # as a string.
  module Handlers
    
    # Decodes JSON Twitter API responses
    class JSONHandler
    
      def decode_response(res)
        json_result = JSON.parse(res)
        load_recursive(json_result)
      end
      
      private
        def load_recursive(value)
          if value.kind_of? Hash
            build_struct(value)
          elsif value.kind_of? Array
            value.map{|v| load_recursive(v)}
          else
            value
          end
        end
      
        def build_struct(hash)
          struct = TwitterStruct.new
          hash.each do |key,v|
            struct.send("#{key}=",load_recursive(v))
          end
          struct
        end
      
    end
    
    # Decodes XML Twitter API responses
    class XMLHandler
      
      #Known nodes returned by twitter that contain arrays
      ARRAY_NODES = ['ids','statuses','users']
      
      def decode_response(res)
        xml = REXML::Document.new(res)
        load_recursive(xml.root)
      end
      
      private
        def load_recursive(node)
          if array_node?(node)
            node.elements.map {|e| load_recursive(e)}
          elsif node.elements.size > 0
            build_struct(node)
          elsif node.elements.size == 0
            value = node.text
            fixnum?(value) ? value.to_i : value
          end
        end
      
        def build_struct(node)
          ts = TwitterStruct.new
          node.elements.each do |e|
            ts.send("#{e.name}=",load_recursive(e))  
          end
          ts
        end
        
        # Most of the time Twitter specifies nodes that contain an array of 
        # sub-nodes with a type="array" attribute. There are some nodes that 
        # they dont' do that for, though, including the <ids> node returned 
        # by the social graph methods. This method tries to work in both situations.
        def array_node?(node)
          node.attributes['type'] == 'array' || ARRAY_NODES.include?(node.name)
        end
      
        def fixnum?(value)
          value =~ /^\d+$/
        end
    end
    
    # Just echoes back the response body. This is primarily used for unknown formats
    class StringHandler
      def decode_response(res)
        res
      end
    end
  end
end