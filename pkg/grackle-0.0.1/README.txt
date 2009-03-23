grackle
    by Hayes Davis
    http://www.appozite.com
    http://hayesdavis.net

== DESCRIPTION
Grackle is a lightweight Ruby wrapper around the Twitter REST and Search APIs. It's based on my experience using the 
Twitter API to build http://cheaptweet.com. The main goal of Grackle is to never require a release when the Twitter 
API changes (which it often does) or in the face of a particular Twitter API bug. As such it is somewhat different 
from other Twitter API libraries. It does not try to hide the Twitter "methods" under an access layer nor does it 
introduce concrete classes for the various objects returned by Twitter. Instead, calls to the Grackle client map 
directly to Twitter API URLs. The objects returned by API calls are generated as OpenStructs on the fly and make no 
assumptions about the presence or absence of any particular attributes. Taking this approach means that changes to 
URLs used by Twitter, parameters required by those URLs or return values will not require a new release. It 
will potentially require, however, some modifications to your code that uses Grackle. 

==USING GRACKLE

===Creating a Grackle::Client
  require 'grackle'
  client = Grackle::Client(:username=>'your_user',:password=>'yourpass')

See Grackle::Client for more information about valid arguments to the constructor including for custom headers and SSL.

===Grackle Method Syntax
Grackle uses a method syntax that corresponds to the Twitter API URLs with a few twists. Where you would have a slash in 
a Twitter URL, that becomes a "." in a chained set of Grackle method calls. Each call in the method chain is used to build 
Twitter URL path until a particular call is encountered which causes the request to be sent. Methods which will cause a 
request to be execute include:
  *A method call ending in "?" will cause an HTTP GET to be executed
  *A method call ending in "!" will cause an HTTP POST to be executed
  *If a valid format such as .json, .xml, .rss or .atom is encounted, a get will be executed with that format
  *A format method can also include a ? or ! to determine GET or POST in that format respectively

===GETting Data
Invoking the API method "/users/show" in XML format for the Twitter user "some_user" looks like
  client.users.show.xml :id=>'some_user' #http://twitter.com/users/show.xml?id=some_user

Or using the JSON format:
  client.users.show.json :id=>'some_user' #http://twitter.com/users/show.json?id=some_user

Or, since Twitter also allows certain ids to be part of their URLs, this works:
  client.users.show.some_user.json #http://twitter.com/users/show/some_user.json

The client has a default format of :json so if you want to use the above call with the default format you can do:
  client.users.show.some_user? #http://twitter.com/users/show/some_user.json

If you include a "?" at the end of any method name, that signals to the Grackle client that you want to execute an HTTP GET request.

===POSTing data
To use Twitter API methods that require an HTTP POST, you need to end your method chain with a bang (!)

For example, to update the authenticated user's status using the XML format:
  client.statuses.update.xml! :status=>'this status is from grackle' #POST to http://twitter.com/statuses/update.xml

Or, with JSON
  client.statuses.update.json! :status=>'this status is from grackle' #POST to http://twitter.com/statuses/update.json

Or, using the default format
  client.statuses.update! :status=>'this status is from grackle' #POST to http://twitter.com/statuses/update.json

===Search
Search works the same as everything else but your queries get submitted to search.twitter.com
  client.search? :q=>'grackle' #http://search.twitter.com/search.json?q=grackle

===Parameter handling
  *All parameters are URL encoded as necessary.
  *If you use a File object as a parameter it will be POSTed to Twitter in a multipart request.
  *If you use a Time object as a parameter, .httpdate will be called on it and that value will be used

===Return Values
Regardless of the format used, Grackle returns a Grackle::TwitterStruct (which is mostly just an OpenStruct) of data. The attributes 
available on these structs correspond to the data returned by Twitter.

===Dealing with Errors
If the request to Twitter does not return a status code of 200, then a TwitterError is thrown. This contains the HTTP method used, 
the full request URI, the response status, the response body in text and a response object build by parsing the formatted error 
returned by Twitter. It's a good idea to wrap your API calls with rescue clauses for Grackle::TwitterError.

===Formats
Twitter allows you to request data in particular formats. Grackle currently supports JSON and XML. The Grackle::Client has a 
default_format you can specify. By default, the default_format is :json. If you don't include a named format in your method 
chain as described above, but use a "?" or "!" then the Grackle::Client.default_format is used.

== REQUIREMENTS:

You'll need the following gems to use all features of Grackle:
  *json_pure
  *httpclient 

== INSTALL:

sudo gem install grackle

== LICENSE:

(The MIT License)

Copyright (c) 2009

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
