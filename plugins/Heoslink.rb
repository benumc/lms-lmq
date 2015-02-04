
require 'socket'
require 'json'

module Heoslink
  extend self
@@HeosServerAddress = ""
@@playerDB = {}

def GetServerAddress
  begin
    addr = ['239.255.255.250', 1900]# broadcast address
    udp = UDPSocket.new
    udp.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
    data = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: urn:schemas-denon-com:device:ACT-Denon:1\r\n"
    udp.send(data, 0, addr[0], addr[1])
    data,address = udp.recvfrom(1024)
    @@HeosServerAddress = address[2]
    udp.close
    #puts @@HeosServerAddress
    @@sock = TCPSocket.open(@@HeosServerAddress,1255)
  rescue
    #puts "Could Not Find Server. Retry in 10 seconds..."
    sleep(10)
    retry
  end
end

def SendToPlayer(msg)
  puts "Sending Message: heos://#{msg}"
  @@sock.puts("heos://#{msg}")
  c = ""
  m = ""
  until c == msg.split('?')[0] && m !~ /command under process/
    r = JSON.parse(URI.decode(@@sock.gets))
    c = r["heos"]["command"]
    m = r["heos"]["message"]
    #puts r
  end
  puts "Received From Heos: #{JSON.pretty_generate(r)}"
  return r
end

def Login(un,pw)
  r = SendToPlayer("system/sign_in?un=#{un}&pw=#{pw}")
  #r = SendToPlayer("system/check_account")
  #while r["heos"]["message"] == "signed_out"
  #  sleep(1)
  #  r = SendToPlayer("system/check_account")
  #end
  return true
end

def GetPlayerId(devName)
  r = SendToPlayer("players/get_players")
  if r
    r["payload"].each do |s|
      if s["name"].downcase == devName
        return s["pid"]
      end
    end
  end
  return nil
end

  #Server Command Handling Below

def Play(playerId,titleId,startAtSecs,audioIndex)
  if playerId && titleId && startAtSecs && audioIndex
    StopProgress(playerId) if $playerDB[playerId][:NowPlaying]
    player = $playerDB[playerId]
    startAtSecs = -1 if startAtSecs == 0
    b = JSON.parse(ServerGET("Users/#{player["UserId"]}/Items/#{titleId}?",playerId).body)
    b2 = JSON.parse(ServerGET("Items/#{b["Id"]}/MediaInfo?userId=#{player["UserId"]}",playerId).body) unless b["Path"]
    #puts b2
    p = b["Path"] || b2["MediaSources"][0]["Path"] 
    #puts "Path: #{p}"
    SendToPlayer(playerId,"QVMPF -n #{audioIndex} -l #{startAtSecs} #{p}\r")
    player[:Mode] = "play"
    player[:Time] = Time.new.to_i - startAtSecs
    player[:NowPlaying] = b
    StartProgress(playerId)
  end
end

def Pause(playerId)
  if playerId
    player = $playerDB[playerId]
    SendToPlayer(playerId,"QPLPAUSE\r")
    player[:Mode] = "pause"
    player[:Time] = Time.new.to_i - player[:Time].to_i - 2
    UpdateProgress(playerId)
  end
end

def Stop(playerId)
  if playerId && $playerDB[playerId][:NowPlaying]
    player = $playerDB[playerId]
    StopProgress(playerId)
    SendToPlayer(playerId,"QSTOP\r")
    player[:Mode] = "stop"
    player[:NowPlaying] = nil
    player[:Time] = 0
  end
end

def StandardBrowse(mId)
  puts mId
  r = SendToPlayer("browse/browse?#{mId}")
  puts r
  b = []
  if r
    r["payload"].each do |s|
      s["sid"] ? id = "sid=#{s["sid"]}" : id = "#{mId.split("&cid=")[0]}&cid=#{s["cid"]}"
      img = s["image_url"] || s["image_uri"]
      h = {}
      h[:id] = id
      h[:cmd] = s["type"]
      h[:text] = s["name"].encode("ASCII", {:invalid => :replace, :undef => :replace, :replace => ''})
      h[:icon] = img if img.length > 0
      h[:isContext] = true if s["playable"] == "yes"
      b << h
    end
  end
  #puts "Heos Menu :\n#{b}"
  return b
end

#Savant Request Handling Below********************

def SavantRequest(hostname,cmd,req)
  #puts "Hostname:\n#{hostname}\n\nCommand:\n#{cmd}\n\nRequest:\n#{req}"
  h = Hash[req.map {|e| e.split(":",2) if e.to_s.include? ":"}]
  unless @@playerDB[hostname["name"]] && @@playerDB[hostname["name"]][:SignedIn]
    @@playerDB[hostname["name"]] = {
      :SignedIn => Login(hostname["un"],hostname["pw"]),
      :HeosId => GetPlayerId(hostname["name"])
    }
  end
  return send(cmd,hostname["name"],h["id"])
end

def TopMenu(pNm,mId)
  r = SendToPlayer("browse/get_music_sources")
  b = []
  if r
    r["payload"].each do |s|
      b[b.length] = {
        :id =>"sid=#{s["sid"]}",
        :cmd =>s["type"],
        :text =>s["name"],
        :icon =>s["image_url"] || s["image_uri"]
      }
    end
  end
  return b
end

def Status(pNm,mId)
  return {}
end


def ContextMenu(pId,mId)

end

def NowPlaying(pId,mId)
  
end

def AutoStart(pId,mId)
  
end

def SkipToTime(pId,mId)
  
end

def TransportPlay(pId,mId)
  
end

def TransportPause(pId,mId)
  
end

def TransportStop(pId,mId)
  
end

def TransportFastReverse(pId,mId)
  
end

def TransportFastForward(pId,mId)
  
end

def TransportSkipReverse(pId,mId)
  
end

def TransportSkipForward(pId,mId)
  
end

def PowerOff(pId,mId)
  
end

def PowerOn(pId,mId)
  
end

def VolumeUp(pId,mId)
  
end

def VolumeDown(pId,mId)
  
end

def SetVolume(pId,mId)
  
end

def MuteOn(pId,mId)
  
end

def MuteOff(pId,mId)
  
end

#Plugin defined requests below ********************************

def heos_service(pNm,mId)
  return StandardBrowse(mId)
end

def music_service(pNm,mId)
  return StandardBrowse(mId)
end

def heos_server(pNm,mId)
  return StandardBrowse(mId)
end

def container(pNm,mId)
  return StandardBrowse(mId)
end

def album(pNm,mId)
  return StandardBrowse(mId)
end

def artist(pNm,mId)
  return StandardBrowse(mId)
end

def genre(pNm,mId)
  return StandardBrowse(mId)
end

def song(pNm,mId)
  
end

GetServerAddress()
end
