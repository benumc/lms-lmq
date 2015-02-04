#!/usr/bin/env ruby

require 'net/http'

module Squeezebox
  extend self

def LMSsetup
  addr = ['239.255.255.250', 1900]# broadcast address
  udp = UDPSocket.new
  udp.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
  data = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 10\r\nST: urn:schemas-upnp-org:device:MediaServer:1\r\n"
  udp.send(data, 0, addr[0], addr[1])
  begin
    data,address = udp.recvfrom(1024)
  end until data.include? "LogitechMediaServer"
  #puts "Data:\n#{data.inspect}\n\nAddress:\n#{address.inspect}\n"
  /Location: http:\/\/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}):(\d+)\//.match(data)
  @@squeezeHost = $1
  @@squeezePort = $2
  udp.close
end

def serverPost(head,msg)
  h = head.split("\r\n")
  url = h[0].split(" ")[1]
  h.shift
  uri = URI("http://#{@@squeezeHost}:#{@@squeezePort}#{url}")
  headers = {}
  h.each do |e|
    e1,e2=e.split(": ")
    headers[e1] = e2
  end
  http = Net::HTTP.new(uri.host, uri.port)
  http.read_timeout = 500
  begin
    response = http.post(uri.path,msg,headers)
    return response
  rescue
    #puts "response timeout:\n#{headers.inspect}\n\n#{msg}"
  end
end

def SqueezeConnect(head,msg)
  blocal = false
  if /mac:(..:..:..:..:..:..)/.match(msg)
    m = @@NetplayMac[$1]
    curMac = $1
    msg.gsub!(/\"params\":\[.+\,\[/,'"params":["'+curMac+'",[')
  end
  #puts "************\nSavant Request:\r\n#{msg.inspect}" unless /"status","-","1"/.match(msg)
  data = "#{head}\r\n\r\n#{msg}"
  
  
#puts "************\nSqueeze Reply:\r\n#{msg}"# unless msg.length > 10000 || /"status","-","1"/.match(msg)
  return serverPost(head,msg)
end

LMSsetup()

end
