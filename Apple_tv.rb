
require 'net/http'
require "rexml/document"
require 'zlib'
require 'stringio'

include REXML


module Apple_tv
  extend self
@@playerDB = {}

def gunzip(data)
  io = StringIO.new(data, "rb")
  gz = Zlib::GzipReader.new(io)
  decompressed = gz.read
end
  
def ReadFromRemote(sock)
  data = sock.gets("\n")
  if data.include? "HTTP"
    sock.gets("\r\n\r\n")
    /GET \/([^ ]+) HTTP/.match(data)
    data = $1
  end
  return data
end

def ServerGET(ip,url)
  uri = URI.parse("http://#{ip}:3689#{url}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.read_timeout = 500
  req = Net::HTTP::Get.new(uri.request_uri)
  req['Host']= "#{ip}:3689"
  req['User-Agent'] = "iPod"
  req['Accept'] = "text/html,application/xhtml+xml,application/xml"
  req['Accept-Language'] = "en-us"
  req['Connection'] = "keep-alive"
  req['Viewer-Only-Client'] = 1
  req['Client-Daap-Version'] = 3.10
  r = http.request(req)
  return r
end

def ServerPOST(ip,url,data)
  uri = URI("http://#{ip}:3689#{url}")
  http = Net::HTTP.new(uri.host,uri.port)
  req = Net::HTTP::Post.new(URI.escape(url))
  req['Host']= "#{ip}:3689"
  req['User-Agent'] = "iPod"
  req['Accept'] = "text/html,application/xhtml+xml,application/xml"
  req['Accept-Language'] = "en-us"
  req['Connection'] = "keep-alive"
  req['Viewer-Only-Client'] = 1
  req['Client-Daap-Version'] = 3.10
  req.body = data
  r = http.request(req)
  return r
end

def AppleTVReply(sock)
  r = "cmpg\x00\x00\x00\x08\x00\x00\x00\x00\x00\x00\x00\x01"+
    "cmnm\x00\x00\x00\x06Savant"+
    "cmty\x00\x00\x00\x04iPod"
  r = "cmpa\x00\x00\x00#{r.length.chr}" + r
  sock.write "HTTP/1.1 200 OK\r\n" +
     "Content-Length: #{r.length}\r\n\r\n" + r
  sock.close
end

def AppleTVpair()
  require File.expand_path(File.dirname(__FILE__)) + '/net/dns/mdns-sd'
  handle = Net::DNS::MDNSSD.register('0000000000000000000000000000000000000001',
                          '_touch-remote._tcp', 
                          'local', 12003,
                          {"Pair"=>"0000000000000001",
                            "txtvers"=>"1",
                            "RemN"=>"Remote",
                            "DvTy"=>"iPod",
                            "RemV"=>"10000",
                            "DvNm"=>"Savant"
                           })
  server = TCPServer.open(12003)
  sock = server.accept
  port, ip = Socket.unpack_sockaddr_in(sock.getpeername)
  data = ReadFromRemote(sock)
  AppleTVReply(sock)
  sock.close
  return true
end

def AppleTVlogin(ip)
  begin
    r = ServerGET(ip,"/login?pairing-guid=0x0000000000000001").body
    /mlid....(....)/.match(r)
    sid = $1.unpack('H*')[0].to_i(16)
    return sid
  rescue
    AppleTVpair()
    retry
  end
end

def ParseDAAP(buffer)
  
  buffer = StringIO.new(buffer)
  
  ret = {}
  puts "begin parsing"
  buffer.read(8)
  while !buffer.eof?   
    
    code = buffer.read(4).to_sym
    length = buffer.read(4).unpack('N').first
    data = buffer.read(length)
    ret[code] = data
    
  end
  ret
end

def SendTransport(pId,data)
  puts "Send To Player #{data.inspect}"
  ServerPOST(pId[:address],"/ctrl-int/1/controlpromptentry?prompt-id=#{pId[:promptId]}&session-id=#{pId[:sessionId]}",data)
  pId[:promptId] += 1
end

#Savant Request Handling Below********************

def SavantRequest(hostname,cmd,req)
  puts "Cmd: #{cmd}        Req: #{req.inspect}" unless req.include? "status"
  h = Hash[req.select { |e|  e.include?(":")  }.map {|e| e.split(":") if e && e.to_s.include?(":")}]
  puts @@playerDB.inspect
  unless @@playerDB[hostname["address"]]
    @@playerDB[hostname["address"]] = {}
    @@playerDB[hostname["address"]][:address] = hostname["address"]
  end
  return nil if @@playerDB[hostname["address"]][:pairing] == true
  unless @@playerDB[hostname["address"]][:sessionId]
    @@playerDB[hostname["address"]][:pairing] = true
    @@playerDB[hostname["address"]][:sessionId] = AppleTVlogin(@@playerDB[hostname["address"]][:address])
    @@playerDB[hostname["address"]][:pairing] = false
    @@playerDB[hostname["address"]][:promptId]=1
    @@playerDB[hostname["address"]][:promptThread] = Thread.new do
      loop do
        p = "GET /controlpromptupdate?prompt-id=#{@@playerDB[hostname["address"]][:promptId]}"+
        "&session-id=#{@@playerDB[hostname["address"]][:sessionId]} HTTP/1.1\r\n"+
        "Host: #{@@playerDB[hostname["address"]][:address]}:3689\r\n"+
        "User-Agent: iPod\r\n"+
        "Accept: text/html,application/xhtml+xml,application/xml\r\n"+
        "Accept-Language: en-us\r\n"+
        "Connection: keep-alive\r\n"+
        "Viewer-Only-Client: 1\r\n"+
        "Client-Daap-Version: 3.10\r\n\r\n"
        sock = TCPSocket.open(@@playerDB[hostname["address"]][:address],3689)
        sock.write(p)
        @@playerDB[hostname["address"]][:promptId] += 1
        h = sock.gets("\r\n\r\n")
        /Content-Length: ([^\r\n]+)\r\n/.match(h)
        l = $1.to_i
        if l
          r = ""
          while r.length < l
            r << sock.read(l-r.length)
          end
          #puts h+r.inspect
        end
        sleep 10
      end
    end
  end
  r = send(cmd,@@playerDB[hostname["address"]],h["id"] || "",h)
  puts "Cmd: #{cmd}        Rep: #{r.inspect}" unless req.include? "status"
  return r
end

def TopMenu(pId,mId,parameters)
  puts "TopMenu"
  b = [{:id=>"Input",:cmd=>"Input",:text=>"Keyboard",:iInput=>true},{:id=>"home",:cmd=>"Home",:text=>"Home"}]
  return b
end

def Status(pId,mId,parameters)
 #puts "Command not supported: #{mId}"
  r = ServerGET(pId[:address],"/ctrl-int/1/playstatusupdate?revision-number=1&session-id=#{pId[:sessionId]}").body
  r = gunzip(r)#.force_encoding("ASCII")
  r = ParseDAAP(r)
  return if r.nil?
  mode = case r[:caps]
    when "\x04"
      "play"
    when "\x03"
      "pause"
    else
      "stop"
    end
  rTime = (r[:cant]||"").unpack('H*')[0].to_i(16)/1000
  tTime = (r[:cast]||"").unpack('H*')[0].to_i(16)/1000
  pTime = tTime-rTime
  i = []
  r[:cann].gsub!("\x00","") if r[:cann]
  r[:cana].gsub!("\x00","") if r[:cana]
  r[:canl].gsub!("\x00","") if r[:canl]
  i << r[:cann]
  i << r[:cana]
  i << r[:canl]
  i = i.compact
  puts i.inspect
  art = "http://#{pId[:address]}/ctrl-int/1/nowplayingartwork?mw=600&mh=600&session-id=#{pId[:sessionId]}"
  body = {
      :Mode => mode,
      :Id => "id",
      :Time => pTime,
      :Duration => tTime,
      :Info => i,
      :Artwork => art
    }
    puts body.inspect
  return body
end

def ContextMenu(pId,mId,parameters)
 #puts "Command not supported: #{mId}"
  
end

def NowPlaying(pId,mId,parameters)
 #puts "Command not supported: #{mId}"
  
end

def AutoStart(pId,mId,parameters)
 #puts "Command not supported: #{mId}"
  
end

def SkipToTime(pId,mId,parameters)
 #puts "Command not supported: #{mId}"
end

def TransportPlay(pId,mId,parameters)
  ServerGET(pId[:address],"/ctrl-int/1/play?session-id=#{pId[:sessionId]}")
end

def TransportPause(pId,mId,parameters)
  ServerGET(pId[:address],"/ctrl-int/1/pause?session-id=#{pId[:sessionId]}")
end

def TransportStop(pId,mId,parameters)
 #puts "Command not supported: #{mId}"
end

def TransportFastReverse(pId,mId,parameters)
  ServerGET(pId[:address],"/ctrl-int/1/beginrew?session-id=#{pId[:sessionId]}")
end

def TransportFastForward(pId,mId,parameters)
  ServerGET(pId[:address],"/ctrl-int/1/beginff?session-id=#{pId[:sessionId]}")
end

def TransportSkipReverse(pId,mId,parameters)
  ServerGET(pId[:address],"/ctrl-int/1/previtem?session-id=#{pId[:sessionId]}")
end

def TransportSkipForward(pId,mId,parameters)
  ServerGET(pId[:address],"/ctrl-int/1/nextitem?session-id=#{pId[:sessionId]}")
end

def TransportRepeatOn(pId,mId,parameters)
  ServerGET(pId[:address],"/ctrl-int/1/setproperty?dacp.repeatstate=1&session-id=#{pId[:sessionId]}")
end

def TransportRepeatOff(pId,mId,parameters)
  ServerGET(pId[:address],"/ctrl-int/1/setproperty?dacp.repeatstate=0&session-id=#{pId[:sessionId]}")
end

def TransportShuffleOn(pId,mId,parameters)
  ServerGET(pId[:address],"/ctrl-int/1/setproperty?dacp.shufflestate=1&session-id=#{pId[:sessionId]}")
end

def TransportShuffleOff(pId,mId,parameters)
  ServerGET(pId[:address],"/ctrl-int/1/setproperty?dacp.shufflestate=0&session-id=#{pId[:sessionId]}")
end

def TransportMenu(pId,mId,parameters)
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x04menu")
end

def TransportUp(pId,mId,parameters)
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchDown&time=0&point=20,275")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=1&point=20,270")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=2&point=20,265")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=3&point=20,260")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=4&point=20,255")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=5&point=20,250")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1BtouchUp&time=6&point=20,250")
end

def TransportDown(pId,mId,parameters)
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchDown&time=0&point=20,250")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=1&point=20,255")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=2&point=20,260")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=3&point=20,265")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=4&point=20,270")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=5&point=20,275")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1BtouchUp&time=6&point=20,275")
end

def TransportLeft(pId,mId,parameters)
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1EtouchDown&time=0&point=75,100")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=1&point=70,100")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=3&point=65,100")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=4&point=60,100")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=5&point=55,100")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=6&point=50,100")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1BtouchUp&time=7&point=50,100")
end

def TransportRight(pId,mId,parameters)
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchDown&time=0&point=50,100")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=1&point=55,100")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=3&point=60,100")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=4&point=65,100")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=5&point=70,100")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1DtouchMove&time=6&point=75,100")
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x1BtouchUp&time=7&point=75,100")
end

def TransportSelect(pId,mId,parameters)
 SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x06select")
end

def PowerOff(pId,mId,parameters)
 puts "Command not supported: #{mId}"
end

def PowerOn(pId,mId,parameters)
 puts "Command not supported: #{mId}"
end

def Search(pId,mId,parameters)
 puts "Command not supported: #{mId}"
end

def VolumeUp(pId,mId,parameters)
 puts "Command not supported: #{mId}"
end

def VolumeDown(pId,mId,parameters)
 puts "Command not supported: #{mId}"
end

def SetVolume(pId,mId,parameters)
 puts "Command not supported: #{mId}"
end

def MuteOn(pId,mId,parameters)
 puts "Command not supported: #{mId}"
end

def MuteOff(pId,mId,parameters)
 puts "Command not supported: #{mId}"
end

def MuteOff(pId,mId,parameters)
 puts "Command not supported: #{mId}"
end
#plugin defined requests below ************

def Home(pId,mId,parameters)
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x30cmbe\x00\x00\x00\x07topmenu")
end

def Input(pId,mId,parameters)
  t = parameters["search"]
  SendTransport(pId,"cmcc\x00\x00\x00\x01\x33cmbe\x00\x00\x00\x0CPromptUpdatecmte\x00\x00\x00#{t.length.chr}#{t}")

end

end