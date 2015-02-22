
require 'net/http'
require "rexml/document"
include REXML

module Playon
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

@@PlayonServer = GetServerAddress().split("|")[0]
puts "PlayonServer : #{@@PlayonServer}"

def ServerGET(url)
  uri = URI.parse("http://#{@@PlayonServer}#{url}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.read_timeout = 500
  req = Net::HTTP::Get.new(uri.request_uri)
  r = http.request(req)
  #puts r.body
  return r.body.encode("ASCII", {:invalid => :replace, :undef => :replace, :replace => ''})
end

def SendToPlayer(add,msg)
  uri = URI.parse("http://#{add}/requests/status.xml#{msg}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.read_timeout = 500
  req = Net::HTTP::Get.new(uri.request_uri)
  puts add,msg
  r = http.request(req)
  return r.body
end

def Play(pId,url,mId,start=0)
  SendToPlayer(pId,"?command=in_play&input=#{url}")
  @@playerDB[pId][:NowPlaying] = mId
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
  puts "Req: #{req.inspect}"
  h = Hash[req.map {|e| e.split(":") if e e.to_s.include? ":"}]
  @@playerDB[hostname["address"]] ||= {}
  return send(cmd,hostname["address"],h["id"] || "")
end

def TopMenu(pId,mId)
  puts "TopMenu"
  @@playerDB[pId["address"]] ||= {} 
  r = Document.new ServerGET("/data/data.xml")
  b = []
  r.elements["catalog"].each do |element| 
    #puts element.attributes
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

def Status(pId,mId)
  t = @@playerDB[pId]
  body = {}
  if t[:Mode]
    t[:Mode] == "pause" ? pTime = t[:Time] : pTime = Time.new.to_i - t[:Time]
   #puts t[:NowPlaying]
    r = Document.new ServerGET(t[:NowPlaying])
   #puts r.to_s
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
 #puts "Command not supported: #{mId}"
end

def TransportPlay(pId,mId)
 #puts "Play #{pId.inspect} #{mId.inspect}"
  if @@playerDB[pId][:Mode] == "pause"
    Resume(pId)
  end
end

def TransportPause(pId,mId)
 #puts "Pause: #{@@playerDB[pId].inspect} #{mId.inspect}"
  if @@playerDB[pId][:Mode] == "play"
    Pause(pId)
  end
end

def TransportStop(pId,mId)
  Stop(pId)
end

def TransportFastReverse(pId,mId)
 #puts "Command not supported: #{mId}"
end

def TransportFastForward(pId,mId)
 #puts "Command not supported: #{mId}"
end

def TransportSkipReverse(pId,mId)
 #puts "Command not supported: #{mId}"
end

def TransportSkipForward(pId,mId)
 #puts "Command not supported: #{mId}"
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
 #puts "Command not implemented: #{mId}"
end

def VolumeDown(pId,mId)
 #puts "Command not implemented: #{mId}"
end

def SetVolume(pId,mId)
 #puts "Command not implemented: #{mId}"
end

def MuteOn(pId,mId)
 #puts "Command not implemented: #{mId}"
end

def MuteOff(pId,mId)
 #puts "Command not implemented: #{mId}"
end

#plugin defined requests below ************

def folder(pId,mId)
  r = Document.new ServerGET(mId)
  b = []
  art = r.root.attributes["art"]
  art ||= "/images/folders/folder_2_0.png?rsm=pz&width=128&height=128&rst=16"
  r.elements["group"].each do |element|
    l = b.length
    b[l] = {}
    b[l][:id] = element.attributes["href"]
    b[l][:text] = element.attributes["name"]
    b[l][:cmd] = element.attributes["type"]
    if art || element.attributes["art"]
      b[l][:icon] ="http://#{@@PlayonServer}#{element.attributes["art"] || art}"
    end
  end
  return b
end

def video(pId,mId)
 #puts pId,mId
  r = Document.new ServerGET(mId)
  b = [{
    :icon =>"http://#{@@PlayonServer}#{r.root.attributes["art"]}",
    :text => r.root.attributes["name"],
    :cmd => r.root.attributes["type"],
    :text => r.root.attributes["name"]
  }]
  src = r.elements["group"].elements["media"].attributes["src"]
  src = "http://#{@@PlayonServer}/#{src}"
  Play(pId,src,mId)
  return {}
end

end
