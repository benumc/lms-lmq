
require 'net/http'
require "rexml/document"
include REXML

module Playon_chromecast
  extend self
@@playerDB = {}
puts "playon loading"
def GetServerAddress
  uri = URI.parse("http://m.playon.tv/q.php")
 #puts uri
  http = Net::HTTP.new(uri.host, uri.port)
  req = Net::HTTP::Get.new(uri.request_uri)
  r = http.request(req)
  return r.body
end

@@Handshake = "GET / HTTP/1.1\r\n"\
"Connection: Upgrade\r\n"\
"Pragma: no-cache\r\n"\
"Cache-Control: no-cache\r\n"\
"Upgrade: websocket\r\n"\
"Sec-WebSocket-Version: 13\r\n"\
"User-Agent: Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2272.74 Safari/537.36\r\n"\
"Accept-Language: en-US,en;q=0.8\r\n"\
"Sec-WebSocket-Key: N+atCj3qEevQsLWU0z+/Wg==\r\n"\
"Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits\r\n\r\n"

@@PlayonServer = GetServerAddress().split("|")[0]
puts "PlayonServer : #{@@PlayonServer}"

def ServerGET(url)
  puts url
  uri = URI.parse("http://#{@@PlayonServer}#{url}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.read_timeout = 500
  req = Net::HTTP::Get.new(uri.request_uri)
  r = http.request(req)
  #puts r.body
  return r.body.encode("ASCII", {:invalid => :replace, :undef => :replace, :replace => ''})
end

def CreateWebSocket(pId)
    pId[:Thread].kill if pId[:Thread]
    Reconnect(pId)
    begin
      pId[:Socket] = TCPSocket.open(pId[:sockAddress],pId[:sockPort])
    rescue
      puts "Failed to create websocket."
      puts pId[:sockAddress],pId[:sockPort]
      return
    end
    pId[:Socket].write(@@Handshake)
    puts pId[:Socket].gets("\r\n\r\n")
    pId[:Thread] = Thread.new do
      puts "Listening"
      while true
        begin
          m = pId[:Socket].recv(1)
        rescue
          puts "Connection to PlayOn Lost"
          pId[:Socket] = nil
          break
        end
        pId[:LastPacket] = Time.new.to_i
        if m.empty?
          pId[:Socket] = nil
          puts "websocket closed"
          break
        end
        m = ''
        l = pId[:Socket].read(1).ord
        l = case l
        when 126
          b = pId[:Socket].read(2)
          l = b.unpack('n*')[0]
        when 127
          b = pId[:Socket].read(8)
          b.reverse! if !@big_endian
          l = b.unpack('Q')[0]
        else
          l
        end
        m = pId[:Socket].read(l)
        m = JSON.parse(m)
        pId[m[0]]=m[1]
      end
    end
end

def Reconnect(pId)
  if Time.new.to_i - pId[:LastPacket].to_i > 5
    puts "Reconnect: #{pId.inspect}"
    pId[:sockAddress] = nil
    r = ServerGET("/playto/chromecast/devices?onlyplayon=true")
    serial = ''
    r.scan(/media_playto name="([^"]+)" serial="([^"]+)"/) do |n,s|
      serial = s if n.casecmp(pId[:address]) == 0
    end
    if serial.length > 1
      r = ServerGET("/playto/chromecast/reconnect?serial=#{serial}")
      /ws:\/\/([^:]*):([^\/]*)\//.match(r)
      pId[:sockAddress] = $1
      pId[:sockPort] = $2.to_i
      pId[:LastPacket] = Time.new.to_i
      CreateWebSocket(pId)
    end
  end
end

def mask_payload(payload)
  masking_key = []
  masking_key << rand(255)
  masking_key << rand(255)
  masking_key << rand(255)
  masking_key << rand(255)
  
  masked_payload = ""
  i = 0
  payload.each_byte do |byte|
    idx = i % 4
    masked_payload << (byte ^ masking_key[idx]).ord.chr
    i += 1
  end
  return masking_key, masked_payload
end

def SendToPlayer(pId,data)
  puts "Send To Player #{data}" unless data.include? "INFO"
  if pId[:Socket]
    frame = ''
    byte1 = 0x1
    byte1 = byte1 | 0b10000000
    frame << byte1.ord.chr
    length = data.size
    byte2 = (length | 0b10000000)
    frame << byte2.ord.chr
    mask_key, masked_payload = mask_payload(data)
    mask_key.each do |m|
      frame << m.ord
    end
    frame << masked_payload if masked_payload
    pId[:Socket].write(frame)
  end
end

def Play(pId,url,mId,start=0)
  r = ServerGET(url)
  /ws:\/\/([^:]*):([^\/]*)\//.match(r)
  pId[:sockAddress] = $1
  pId[:sockPort] = $2.to_i
  Reconnect(pId)
  SendToPlayer(pId,"INFO {}")
  pId[:NowPlaying] = mId
  pId[:Time] = Time.new.to_i + 4
  pId[:Mode] = "play"
end

def Pause(pId)
  #SendToPlayer(pId,"QPLPAUSE\r")
  pId[:Time] = Time.new.to_i - pId[:Time] + 1
  pId[:Mode] = "pause"
end

def Resume(pId)
  #SendToPlayer(pId,"QPLPAUSE\r")
  pId[:Time] = Time.new.to_i -  pId[:Time]
  pId[:Mode] = "play"
end

def Stop(pId)
  #SendToPlayer(pId,"QSTOP\r")
  pId[:Mode] = nil
  pId[:Mode] = stop
  pId[:Time] = 0
end

#Savant Request Handling Below********************

def SavantRequest(hostname,cmd,req)
  #puts "Cmd: #{cmd}        Req: #{req.inspect}" unless req.include? "status"
  h = Hash[req.select { |e|  e.include?(":")  }.map {|e| e.split(":",2) if e && e.to_s.include?(":")}]
  unless @@playerDB[hostname["address"]]
    @@playerDB[hostname["address"]] = {}
    @@playerDB[hostname["address"]][:address] = hostname["address"]
    Reconnect(@@playerDB[hostname["address"]])
  end
  r = send(cmd,@@playerDB[hostname["address"]],h["id"] || "",h)
  #puts "Cmd: #{cmd}        Rep: #{r.inspect}" unless req.include? "status"
  return r
end

def TopMenu(pId,mId,parameters)
  puts "TopMenu"
  r = Document.new ServerGET("/data/data.xml")
  b = []
  r.elements["catalog"].each do |element| 
    #case element.attributes["category"]
    #when "256", "1024"
    #else
      b[b.length] = {
        :id =>element.attributes["href"],
        :cmd =>element.attributes["type"],
        :text =>element.attributes["name"],
        :icon =>"http://#{@@PlayonServer}#{element.attributes["art"]}"
      }
    #end
  end
  return b
end

def Status(pId,mId,parameters)
  Reconnect(pId)
  body = {}
  SendToPlayer(pId,"INFO {}")
  m = pId["MEDIA_STATUS"]
  if m && m["media"]
    print m["playerState"]+"              \r"
    mode = case m["playerState"]
    when "IDLE"
      "pause"
    when "BUFFERING"
      "play"
    when "PLAYING"
      "play"
    when "PAUSED"
      "pause"
    else
      "stop"
    end
    
    id = m["sessionCookie"]
    pTime = m["currentTime"].to_i
    tTime = m["media"]["duration"].to_i
    art = m["media"]["customData"]["thumb"]
    i = []
    i << "Buffering..." if m["playerState"] == "BUFFERING"
    i << "Loading..." if m["playerState"] == "IDLE"
    i << m["media"]["customData"]["title"]
    i << m["media"]["seriesTitle"]
    i << m["media"]["customData"]["description"][0..20]
    i << m["media"]["customData"]["description"][21..40]
    volume = (m["volume"]["level"].to_f * 100).to_i
    body = {
          :Mode => mode,
          :Id => id,
          :Time => pTime,
          :Duration => tTime,
          :Info => i,
          :Artwork => art,
          :Volume => volume
        }
  end
  return body
end

def ContextMenu(pId,mId,parameters)

end

def NowPlaying(pId,mId,parameters)
  
end

def AutoStart(pId,mId,parameters)
  
end

def SkipToTime(pId,mId,parameters)
  puts "Seek: #{parameters["time"].to_i}"
  SendToPlayer(pId,"SEEK {\"position\":#{parameters["time"].to_i}}")
end

def TransportPlay(pId,mId,parameters)
  SendToPlayer(pId,"PLAY {}")
end

def TransportPause(pId,mId,parameters)
  SendToPlayer(pId,"PAUSE {}")
end

def TransportStop(pId,mId,parameters)
  SendToPlayer(pId,"PAUSE {}")
end

def TransportFastReverse(pId,mId,parameters)
 #puts "Command not supported: #{mId}"
end

def TransportFastForward(pId,mId,parameters)
 #puts "Command not supported: #{mId}"
end

def TransportSkipReverse(pId,mId,parameters)
 #puts "Command not supported: #{mId}"
end

def TransportSkipForward(pId,mId,parameters)
 #puts "Command not supported: #{mId}"
end

def PowerOff(pId,mId,parameters)
  SendToPlayer(pId,"PAUSE {}")
end

def PowerOn(pId,mId,parameters)
  SendToPlayer(pId,"PLAY {}")
end

def Input(pId,mId,parameters)
  r = Document.new ServerGET(mId+"&searchterm=dc:description%20contains%20"+parameters["input"])
  b = []
  art = r.root.attributes["art"]
  searchable = r.root.attributes["searchable"]
  art ||= "/images/folders/folder_2_0.png?rsm=pz&width=128&height=128&rst=16"
  b[0] = {:iInput=>1,:text=>"Find"} if searchable=="true"
  r.elements["group"].each do |element|
    l = b.length
    b[l] = {}
    b[l][:id] = element.attributes["href"]
    b[l][:text] = element.attributes["name"]
    b[l][:cmd] = element.attributes["type"]
    if art || element.attributes["art"]
      #b[l][:icon] ="http://#{@@PlayonServer}#{element.attributes["art"] || art}"
      b[l][:icon] ="#{@@PlayonServer}#{element.attributes["art"] || art}"
    end
  end
  return b
end

def Search(pId,mId,parameters)
  r = Document.new ServerGET(mId+"&searchterm=dc:description%20contains%20"+URI.escape(parameters["search"]))
  b = []
  art = r.root.attributes["art"]
  searchable = r.root.attributes["searchable"]
  art ||= "/images/folders/folder_2_0.png?rsm=pz&width=128&height=128&rst=16"
  b[0] = {:iInput=>1,:text=>"Find"} if searchable=="true"
  r.elements["group"].each do |element|
    l = b.length
    b[l] = {}
    b[l][:id] = element.attributes["href"]
    b[l][:text] = element.attributes["name"]
    b[l][:cmd] = element.attributes["type"]
    if art || element.attributes["art"]
      #b[l][:icon] ="http://#{@@PlayonServer}#{element.attributes["art"] || art}"
      b[l][:icon] ="#{@@PlayonServer}#{element.attributes["art"] || art}"
    end
  end
  return b
end

def VolumeUp(pId,mId,parameters)
  m = pId["MEDIA_STATUS"]
  if m
    vol = ((((m["volume"]["level"].to_f * 100).to_i)+2)*0.01).to_s
    SendToPlayer(pId,'VOLUME {"level":'+ vol +',"muted":false}')
  end
end

def VolumeDown(pId,mId,parameters)
  m = pId["MEDIA_STATUS"]
  if m
    vol = ((((m["volume"]["level"].to_f * 100).to_i)-2)*0.01).to_s
    SendToPlayer(pId,'VOLUME {"level":'+ vol +',"muted":false}')
  end
end

def SetVolume(pId,mId,parameters)
  vol = (parameters["volume"].to_f * 0.01).to_s
  SendToPlayer(pId,'VOLUME {"level":'+ vol +',"muted":false}')
end

def MuteOn(pId,mId,parameters)
  m = pId["MEDIA_STATUS"]
  if m
    puts m["volume"]["level"]
    vol = (((m["volume"]["level"].to_f * 100).to_i)*0.01).to_s
    pId[:Volume] = vol
    puts vol
    SendToPlayer(pId,'VOLUME {"level":0,"muted":false}')
  end
end

def MuteOff(pId,mId,parameters)
  m = pId["MEDIA_STATUS"]
  if m
    vol = pId[:Volume] || "0"
    puts vol
    SendToPlayer(pId,'VOLUME {"level":'+ vol +',"muted":false}')
  end
end

#plugin defined requests below ************

def folder(pId,mId,parameters)
  r = Document.new ServerGET(mId)
  b = []
  art = r.root.attributes["art"]
  searchable = r.root.attributes["searchable"]
  art ||= "/images/folders/folder_2_0.png?rsm=pz&width=128&height=128&rst=16"
  b[0] = {:iInput=>1,:text=>"Search",:id=>mId,:cmd=>"search"} if searchable=="true"
  r.elements["group"].each do |element|
    l = b.length
    b[l] = {}
    b[l][:id] = element.attributes["href"]
    b[l][:text] = element.attributes["name"]
    b[l][:cmd] = element.attributes["type"]
    if art || element.attributes["art"]
      #b[l][:icon] ="http://#{@@PlayonServer}#{element.attributes["art"] || art}"
      b[l][:icon] ="#{@@PlayonServer}#{element.attributes["art"] || art}"
    end
  end
  return b
end

def video(pId,mId,parameters)
 #puts pId,mId
  r = Document.new ServerGET(mId)
  b = [{
    :icon =>"http://#{@@PlayonServer}#{r.root.attributes["art"]}",
    :text => r.root.attributes["name"],
    :cmd => r.root.attributes["type"],
    :text => r.root.attributes["name"]
  }]
  src = ""
  r.elements["group"].each do |element|
    puts element
    src = element.attributes["src"] if element.attributes["name"].casecmp(pId[:address]) == 0
  end
  puts src
  Play(pId,src,mId)
  return {}
end

end
