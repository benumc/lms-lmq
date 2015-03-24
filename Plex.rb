
require 'socket'
require 'net/http'
require 'json'
require 'uri'
require "rexml/document"
include REXML

module Plex
  extend self
@@playerDB = {}
@@Head = " HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: "
#@@kodiHost = "192.168.0.5"
#@@kodiPort = 8080

def ServerPost(pId,msg)
  h,p = pId[:address].split(':')
  sock = TCPSocket.open(h,p)
  msg[:id]="1"
  msg[:jsonrpc]="2.0"
  msg = JSON.generate(msg)
  sock.write("POST /jsonrpc#{@@Head}#{msg.length}\r\n\r\n#{msg}")
  h = sock.gets("\r\n\r\n")
  /Content-Length: ([^\r\n]+)\r\n/.match(h)
  #puts h.inspect
  return JSON.parse(sock.read($1.to_i)) if $1
rescue
  puts $!, $@
  return nil
end

def PlexGet(pId,msg)
  url = "http://#{pId[:server]}#{msg}"
  if url.include?('?')
    url << "&X-Plex-Token=#{pId[:token]}"
  else
    url << "?X-Plex-Token=#{pId[:token]}"
  end
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.read_timeout = 500
  req = Net::HTTP::Get.new(uri.request_uri)
  r = http.request(req)
  return r.body
end


def PlayerGet(pId,msg)
  url = "http://#{pId[:server]}#{msg}"
  if url.include?('?')
    url << "&X-Plex-Token=#{pId[:token]}"
  else
    url << "?X-Plex-Token=#{pId[:token]}"
  end
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.read_timeout = 500
  req = Net::HTTP::Get.new(uri.request_uri)
  r = http.request(req)
  return r.body.encode("ASCII", {:invalid => :replace, :undef => :replace, :replace => ''})
rescue
  puts $!, $@
  return nil
end

#Savant Request Handling Below********************

def SavantRequest(hostname,cmd,req)
  puts "Cmd: #{cmd}        Req: #{req.inspect}" unless req.include? "status"
  h = Hash[req.select { |e|  e.include?(":")  }.map {|e| e.split(":") if e && e.to_s.include?(":")}]
  pId = @@playerDB[hostname["address"]]
  unless pId
    @@playerDB[hostname["address"]] = {}
    pId = @@playerDB[hostname["address"]]
    pId[:address] = hostname["address"]
    pId[:server] = hostname["server"] || hostname["address"]
    r = Document.new PlexGet(pId,"")
    pId[:serverId] = r.root.attributes["machineIdentifier"]
    pId[:token] = Dir["token.*"][0]
    pId[:token].slice!("token.") if pId[:token]
  end  
  r = send(cmd,pId,h["id"] || "",h)
  puts "Cmd: #{cmd}        Rep: #{r.inspect}" unless req.include? "status"
  return r
end

def TopMenu(pId,mId,parameters)
  puts "TopMenu"
  b = [{:id=>"Input",:cmd=>"Input",:text=>"Keyboard",:iInput=>true},{:id=>"search",:cmd=>"search",:text=>"Search",:iInput=>true}]
  b.push(*GetPlexMenu(pId,"/library/sections"))
  b.push(*GetPlexMenu(pId,"/channels/all"))
  return b
end

def Status(pId,mId,parameters)
  #puts "Command not supported: #{mId}"
  r = ServerPost(pId,{:method => "Player.GetActivePlayers"})
  #puts r.inspect
  return nil unless r && r["result"] && r["result"] != []
  playid = 1
  r["result"].each {|i| playid = i["playerid"]}
  pId[:playerId] = playid
  s = {
    :method => "Player.GetItem",
    :params => {
      :properties => [
        "art",
        "artist",
        "album",
        "season",
        "episode",
        "genre",
        "showtitle"
      ],
      :playerid => playid
    }
  }
  r = ServerPost(pId,s)["result"]
  #puts r.inspect
  return nil unless r["item"] && r["item"].length > 0
  a = r["item"]["art"]["album.thumb"] ||\
      r["item"]["art"]["tvshow.thumb"] ||\
      r["item"]["art"]["poster"] ||\
      r["item"]["art"]["artist.fanart"] ||\
      r["item"]["art"]["fanart"] ||\
      r["item"]["art"]["thumb"]
  art = "http://#{pId[:address]}/image/#{a.gsub!('%','%25')}" if a
  if art && art.include?("127.0.0.1")
    art = URI.decode(URI.decode(URI.decode(art))).split("url=")[1]
    art.gsub!("127.0.0.1:32400",pId[:server] || pId[:address])
    if art.include?('?')
      art << "&X-Plex-Token=#{pId[:token]}"
    else
      art << "?X-Plex-Token=#{pId[:token]}"
    end
  end
  
  
  id = r["item"]["id"]
   
  i = [r["item"]["label"]]
  i << r["item"]["showtitle"] if (r["item"]["showtitle"]||"").length > 0
  i << r["item"]["album"] if (r["item"]["album"]||"").length > 0
  i << r["item"]["artist"].join(",") if (r["item"]["artist"]||"").length > 0
  if r["item"]["episode"].to_i > 0 && r["item"]["season"].to_i > 0
    i << "Season #{r["item"]["season"]} - Episode #{r["item"]["episode"]}"
  end
  i << r["item"]["genre"].join(",") if (r["item"]["genre"]||"").length > 0
  
  i = i.flatten.compact
  i.map{|e| e.encode("ASCII", {:invalid => :replace, :undef => :replace, :replace => '_'})}
  s = {
    :method => "Player.GetProperties",
    :params => {
      :properties => [
        "playlistid",
        "speed",
        "position",
        "totaltime",
        "time"
      ],
      :playerid => playid
    }
  }
  r = ServerPost(pId,s)["result"]
  return nil if r.nil?
  r["speed"] == 1 ? mode = "play" : mode = "pause"
  
  duration = r["totaltime"]["hours"]*60*60 + r["totaltime"]["minutes"]*60 + r["totaltime"]["seconds"]
  time = r["time"]["hours"]*60*60 + r["time"]["minutes"]*60 + r["time"]["seconds"]
   
  body = {
      :Mode => mode,
      :Id => id,
      :Time => time,
      :Duration => duration,
      :Info => i,
      :Artwork => art
    }
    puts body
  return body
end

def ContextMenu(pId,mId,parameters)
 #puts "Command not supported: #{mId}"
  return nil
  
end

def NowPlaying(pId,mId,parameters)
 #puts "Command not supported: #{mId}"
  return nil
  
end

def AutoStart(pId,mId,parameters)
 #puts "Command not supported: #{mId}"
  return nil
  
end

def SkipToTime(pId,mId,parameters)
  t = parameters["time"].to_i
  s = t % 60
  m = (t / 60) % 60
  h = t / (60 * 60)
  ServerPost(pId,{
    :method => "Player.Seek",
    :params => {
      :playerid => pId[:playerId],
      :value => {
        :seconds => s,
        :minutes => m,
        :hours => h,
      }
    }
    })
  return nil
end

def TransportPlay(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Player.PlayPause",
    :params => {
      :playerid => pId[:playerId],
      :play => "toggle"
    }
    })
  return nil
end

def TransportPause(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Player.PlayPause",
    :params => {
      :playerid => pId[:playerId],
      :play => false
    }
    })
  return nil
end

def TransportStop(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Player.Stop",
    :params => {
      :playerid => pId[:playerId]
    }
    })
  return nil
end

def TransportFastReverse(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Player.SetSpeed",
    :params => {
      :playerid => pId[:playerId],
      :speed => "decrement"
    }
    })
  return nil
end

def TransportFastForward(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Player.SetSpeed",
    :params => {
      :playerid => pId[:playerId],
      :speed => "increment"
    }
    })
  return nil
end

def TransportSkipReverse(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Player.GoTo",
    :params => {
      :playerid => pId[:playerId],
      :to => "previous"
    }
    })
  return nil
end

def TransportSkipForward(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Player.GoTo",
    :params => {
      :playerid => pId[:playerId],
      :to => "next"
    }
    })
  return nil
end

def TransportRepeatOn(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Player.SetRepeat",
    :params => {
      :playerid => pId[:playerId],
      :repeat => "all"
    }
    })
  return nil
end

def TransportRepeatToggle(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Player.SetRepeat",
    :params => {
      :playerid => pId[:playerId],
      :repeat => "cycle"
    }
    })
  return nil
end

def TransportRepeatOff(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Player.SetRepeat",
    :params => {
      :playerid => pId[:playerId],
      :repeat => "off"
    }
    })
  return nil
end

def TransportShuffleToggle(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Player.Shuffle",
    :params => {
      :playerid => pId[:playerId],
      :shuffle => "toggle"
    }
    })
  return nil
end

def TransportShuffleOn(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Player.Shuffle",
    :params => {
      :playerid => pId[:playerId],
      :shuffle => true
    }
    })
  return nil
end

def TransportShuffleOff(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Player.Shuffle",
    :params => {
      :playerid => pId[:playerId],
      :shuffle => false
    }
    })
  return nil
end

def TransportMenu(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Input.Back",
    })
  return nil
end

def TransportUp(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Input.Up",
    })
  return nil
end

def TransportDown(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Input.Down",
    })
  return nil
end

def TransportLeft(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Input.Left",
    })
  return nil
end

def TransportRight(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Input.Right",
    })
  return nil
end

def TransportSelect(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Input.Select",
    })
  return nil
end

def PowerOff(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Player.Stop",
    :params => {
      :playerid => pId[:playerId]
    }
    })
  return nil
end

def PowerOn(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Input.ShowOSD",
    })
  return nil
end

def VolumeUp(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Application.SetVolume",
    :params => {
      :volume => "increment"
    }
    })
  return nil
end

def VolumeDown(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Application.SetVolume",
    :params => {
      :volume => "decrement"
    }
    })
  return nil
end

def SetVolume(pId,mId,parameters)
  v = parameters["volume"].to_i
  ServerPost(pId,{
    :method => "Application.SetVolume",
    :params => {
      :volume => v
    }
    })
  return nil
end

def MuteOn(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Application.SetMute",
    :params => {
      :mute => false
    }
    })
  return nil
end

def MuteOff(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Application.SetMute",
    :params => {
      :mute => true
    }
    })
  return nil
end

def MuteOff(pId,mId,parameters)
  ServerPost(pId,{
    :method => "Application.SetMute",
    :params => {
      :mute => false
    }
    })
  return nil
end

#plugin defined requests below ************

def Input(pId,mId,parameters)
  t = parameters["search"]
  r = ServerPost(pId,{
    :method => "Input.SendText",
    :params => {
      :text => "#{t}",
      :done => true
    }
    })
  return nil
end

def Search(pId,mId,parameters)
  t = parameters["search"]
  b = []
  #b = [{:id=>"Input",:cmd=>"Input",:text=>"Keyboard",:iInput=>true},{:id=>"Search",:cmd=>"Search",:text=>"Search",:iInput=>true}]
  b.push(*GetPlexMenu(pId,"/search?local=1&query=#{parameters["search"]}"))
  #puts b
  return b
end

def Directory(pId,mId,parameters)
  b = []
  #b = [{:id=>"Input",:cmd=>"Input",:text=>"Keyboard",:iInput=>true},{:id=>"Search",:cmd=>"Search",:text=>"Search",:iInput=>true}]
  b.push(*GetPlexMenu(pId,mId))
  return b
end

def GetPlexMenu(pId,url)
  url.gsub!('&','&amp;')
  puts url
  r = Document.new PlexGet(pId,url)
  b = []
  puts r.to_s
  pThumb = r.root.attributes["thumb"]
  r.elements.each("MediaContainer/Video") do |e|
    ic = e.attributes["thumb"]||pThumb
    ic = "http://#{pId[:server]}#{ic}" unless ic.include? 'http://'
    id = e.attributes["key"]
    id = "#{url}/#{id}" unless id.include?("/")  
    if ic.include?('?')
      ic << "&X-Plex-Token=#{pId[:token]}"
    else
      ic << "?X-Plex-Token=#{pId[:token]}"
    end
    b[b.length] = {
      :id =>id,
      :cmd =>"Video",
      :text =>e.attributes["title"].encode("ASCII", {:invalid => :replace, :undef => :replace, :replace => ''}),
      :icon =>ic
    }
  end
  
  r.elements.each("MediaContainer/Directory") do |e|
    ic = e.attributes["thumb"]||pThumb
    ic = "http://#{pId[:server]}#{ic}" unless ic.include? 'http://'
    id = e.attributes["key"]
    id = "#{url}/#{id}" unless id.include?("/")
    if ic.include?('?')
      ic << "&X-Plex-Token=#{pId[:token]}"
    else
      ic << "?X-Plex-Token=#{pId[:token]}"
    end
    b[b.length] = {
      :id =>id,
      :cmd =>"Directory",
      :text =>e.attributes["title"].encode("ASCII", {:invalid => :replace, :undef => :replace, :replace => ''}),
      :icon =>ic
    }
  end
  return b
end

def Video(pId,mId,parameters)
  a,p= pId[:server].split(":")
  PlayerGet(pId,"/player/playback/playMedia?key=#{mId}&machineIdentifier=#{pId[:serverId]}&address=#{a}&port=#{p}")
  return nil
end

end
