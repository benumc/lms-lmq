
require 'socket'

module Kodi
  extend self
@@playerDB = {}

def SendToPlayer(add,msg)
end

def Play(pId,url,mId,start=0)
  SendToPlayer(pId,"QVMPF #{url}\r")
  @@playerDB[pId][:Mode] = mId  
  @@playerDB[pId][:Time] = Time.new.to_i + 4
  @@playerDB[pId][:Mode] = "play"
end

def Pause(pId)
  SendToPlayer(pId,"QPLPAUSE\r")
  @@playerDB[pId][:Time] = Time.new.to_i - @@playerDB[pId][:Time] + 1
  @@playerDB[pId][:Mode] = "pause"
end

def Resume(pId)
  SendToPlayer(pId,"QPLPAUSE\r")
  @@playerDB[pId][:Time] = Time.new.to_i -  @@playerDB[pId][:Time]
  @@playerDB[pId][:Mode] = "play"
end

def Stop(pId)
  SendToPlayer(pId,"QSTOP\r")
  @@playerDB[pId][:Mode] = nil
  @@playerDB[pId][:Mode] = stop
  @@playerDB[pId][:Time] = 0
end

#Savant Request Handling Below********************

def SavantRequest(hostname,cmd,req)
  h = Hash[req.map {|e| e.split(":") if e.to_s.include? ":"}]
  @@playerDB[hostname["address"]] ||= {}
  return send(cmd,hostname["address"],h["id"])
end

def TopMenu(pId,mId)
  @@playerDB[pId["address"]] ||= {} 
  r = Document.new ServerGET("/data/data.xml")
  b = []
  r.elements["catalog"].each do |element| 
    #puts element.attributes
    case element.attributes["category"]
    when "256", "1024"
    else
      b[b.length] = {
        :id =>element.attributes["href"],
        :cmd =>element.attributes["type"],
        :text =>element.attributes["name"],
        :icon =>"http://#{@@PlayonServer}#{element.attributes["art"]}"
      }
    end
  end
  return b
end

def Status(pId,mId)
  t = @@playerDB[pId]
  body = {}
  if t[:Mode]
    t[:Mode] == "pause" ? pTime = t[:Time] : pTime = Time.new.to_i - t[:Time]
    r = Document.new ServerGET(t[:Mode])
    body = {
        :Mode => t[:Mode],
        :Id => t[:Mode].split("id=")[1],
        :Time => pTime,
        :Duration => "",
        :Info => [],
        :Artwork => "http://#{@@PlayonServer}#{r.elements["group"].elements["media"].attributes["art"]}"
      }
    i = []
    i << r.elements["group"].elements["media_title"].attributes["name"] if r.elements["group"].elements["media_title"]
    i << r.elements["group"].elements["series"].attributes["name"] if r.elements["group"].elements["series"]
    i << r.elements["group"].elements["rating"].attributes["name"] if r.elements["group"].elements["rating"]
    i << r.elements["group"].elements["time"].attributes["name"] if r.elements["group"].elements["time"]
    i << r.elements["group"].elements["date"].attributes["name"] if r.elements["group"].elements["date"]
    body[:Info] = i
  end
  return body
end

def ContextMenu(pId,mId)

end

def NowPlaying(pId,mId)
  
end

def AutoStart(pId,mId)
  
end

def SkipToTime(pId,mId)
  puts "Command not supported: #{mId}"
end

def TransportPlay(pId,mId)
  puts "Play #{pId.inspect} #{mId.inspect}"
  if @@playerDB[pId][:Mode] == "pause"
    Resume(pId)
  end
end

def TransportPause(pId,mId)
  puts "Pause: #{@@playerDB[pId].inspect} #{mId.inspect}"
  if @@playerDB[pId][:Mode] == "play"
    Pause(pId)
  end
end

def TransportStop(pId,mId)
  Stop(pId)
end

def TransportFastReverse(pId,mId)
  puts "Command not supported: #{mId}"
end

def TransportFastForward(pId,mId)
  puts "Command not supported: #{mId}"
end

def TransportSkipReverse(pId,mId)
  puts "Command not supported: #{mId}"
end

def TransportSkipForward(pId,mId)
  puts "Command not supported: #{mId}"
end

def PowerOff(pId,mId)
  if @@playerDB[pId][:Mode] == "play"
    Pause(pId)
  end
end

def PowerOn(pId,mId)
  if @@playerDB[pId][:Mode] == "pause"
    Resume(pId)
  end
end

def VolumeUp(pId,mId)
  puts "Command not implemented: #{mId}"
end

def VolumeDown(pId,mId)
  puts "Command not implemented: #{mId}"
end

def SetVolume(pId,mId)
  puts "Command not implemented: #{mId}"
end

def MuteOn(pId,mId)
  puts "Command not implemented: #{mId}"
end

def MuteOff(pId,mId)
  puts "Command not implemented: #{mId}"
end

#plugin defined requests below ************

end
