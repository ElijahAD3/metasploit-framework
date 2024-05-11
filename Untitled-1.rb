##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

class MetasploitModule < Msf::Exploit::Remote
    Rank = NormalRanking
  
    include Msf::Exploit::Remote::HttpServer
  
    def initialize(info = {})
      super(
        update_info(
          info,
          'Name' => 'HttpServer mixin example',
          'Description' => %q{
            Heres an example of using the HttpServer mixin
          },
          'License' => MSF_LICENSE,
          'Author' => [ 'sinn3r' ],
          'References' => [
            [ 'URL', 'http://metasploit.com' ]
          ],
          'Platform' => 'win',
          'Targets' => [
            [ 'Generic', {} ],
          ],
          'DisclosureDate' => '2013-04-01',
          'DefaultTarget' => 0
        )
      )
    end
  
    def on_request_uri(cli, _request)
      html = 'hello'
      send_response(cli, html)
    end
  
  end
  