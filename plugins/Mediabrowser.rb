
require 'net/http'

module Mediabrowser
  extend self

@@blockSize = 1024
@@MovieServerAddress = ""
@@MovieServerID = ""
@@MovieServerName = ""

@@playerDB = {}
@@userDB = {}

def GetServerAddress()
  begin
    addr = ['255.255.255.255', 7359]# broadcast address
    udp = UDPSocket.new
    udp.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
    data = 'who is MediaBrowserServer_v2?'
    udp.send(data, 0, addr[0], addr[1])
    data, addr = udp.recvfrom(1024)
    dat = JSON.parse(data)
    @@MovieServerAddress = dat["Address"].split("http://")[1]
    @@MovieServerID = dat["Id"]
    @@MovieServerName = dat["Name"]
    puts @@MovieServerAddress
    udp.close
  rescue
    puts "Could Not Find Server. Retry in 10 seconds..."
    sleep(10)
    retry
  end
end

GetServerAddress()

def ServerGET(url,playerId)
  uri = URI.parse("http://#{@@MovieServerAddress}/mediabrowser/#{url}&format=json")
  puts uri
  http = Net::HTTP.new(uri.host, uri.port)
  req = Net::HTTP::Get.new(uri.request_uri)
  auth = 'MediaBrowser Client="MovieLMQ", Device="Savant"'
  auth << ', DeviceId="'+playerId+'"'
  auth << ', UserId="'+@@playerDB[playerId]["UserId"]+'"' if @@playerDB[playerId]["UserId"]
  auth << ', Version="1.0.0.0"'
  req["Authorization"] = auth
  req["X-MediaBrowser-Token"] = @@playerDB[playerId]["Token"]
  r = http.request(req)
  #puts r.body
  return r
end

def ServerPOST(url,playerId,formDat)
  uri = URI.parse("http://#{@@MovieServerAddress}/mediabrowser/#{url}&format=json")
  req = Net::HTTP::Post.new(uri.request_uri)
  req.set_form_data(formDat)
  auth = 'MediaBrowser Client="MovieLMQ", Device="Savant"'
  auth << ', DeviceId="'+playerId+'"'
  auth << ', UserId="'+@@playerDB[playerId]["UserId"]+'"' if @@playerDB[playerId]["UserId"]
  auth << ', Version="1.0.0.0"'
  req["Authorization"] = auth.to_s
  req["X-MediaBrowser-Token"] = @@playerDB[playerId]["Token"]
  r = Net::HTTP.start(uri.host, uri.port) do |http|
    http.request(req)
  end
  #puts r.body
  return r
end

def GetUsers(playerId)
  @@userDB = JSON.parse(ServerGET("Users/Public?",playerId).body)
end

def BestImage(imageTags,backdropTags)
  if imageTags["Disc"]
    return "Disc"
  elsif imageTags["Thumb"]
    return "Thumb"
  elsif imageTags["Primary"]
    return "Primary"
  elsif backdropTags[0]
    return "backdrop/0"
  else
    return ""
  end
end

def SendToPlayer(add,msg)
  puts add,msg
  add,p = add.split(":")
  begin
    s = TCPSocket.open(add,p)
    s.write(msg)
  end
end

def StartProgress(playerId)
  player = @@playerDB[playerId]
  if player[:Mode]=="play"
    t = Time.new.to_i - player[:Time].to_i
    p = false
  else
    t = player[:Time].to_i
    p = true
  end
  t = 0 if t == -1
  form_dat = {
    'QueueableMediaTypes'=>'Audio,Video',
    'CanSeek'=>true,
    'ItemId'=>player[:NowPlaying]["Id"],
    'MediaSourceId'=>player[:NowPlaying]["Id"],
    'IsPaused'=>p,
    'IsMuted'=>false,
    'PositionTicks'=>t*10000000,
    'PlayMethod'=>'DirectPlay'
    }
  ServerPOST("Sessions/Playing?",playerId,form_dat).body
end

def UpdateProgress(playerId)
  player = @@playerDB[playerId]
  if player[:Mode]=="play"
    t = Time.new.to_i - player[:Time].to_i
    p = false
  else
    t = player[:Time].to_i
    p = true
  end
  form_dat = {
    'QueueableMediaTypes'=>'Audio,Video',
    'CanSeek'=>true,
    'ItemId'=>player[:NowPlaying]["Id"],
    'MediaSourceId'=>player[:NowPlaying]["Id"],
    'IsPaused'=>p,
    'IsMuted'=>false,
    'PositionTicks'=>t*10000000,
    'PlayMethod'=>'DirectPlay'
    }
  ServerPOST("Sessions/Playing/Progress?",playerId,form_dat)
end

def StopProgress(playerId)
  player = @@playerDB[playerId]
  if player[:Mode]=="play"
    t = Time.new.to_i - player[:Time].to_i
    p = false
  else
    t = player[:Time].to_i
    p = true
  end
  form_dat = {
    'QueueableMediaTypes'=>'Audio,Video',
    'CanSeek'=>true,
    'ItemId'=>player[:NowPlaying]["Id"],
    'MediaSourceId'=>player[:NowPlaying]["Id"],
    'IsPaused'=>p,
    'IsMuted'=>false,
    'PositionTicks'=>t*10000000,
    'PlayMethod'=>'DirectPlay'
    }
  ServerPOST("Sessions/Playing/Stopped?",playerId,form_dat)
end

def Play(playerId,titleId,startAtSecs,audioIndex)
  puts "#{playerId},#{titleId},#{startAtSecs},#{audioIndex}"
  if playerId && titleId && startAtSecs && audioIndex
    StopProgress(playerId) if @@playerDB[playerId][:NowPlaying]
    player = @@playerDB[playerId]
    startAtSecs = -1 if startAtSecs == 0
    b = JSON.parse(ServerGET("Users/#{player["UserId"]}/Items/#{titleId}?",playerId).body)
    b2 = JSON.parse(ServerGET("Items/#{b["Id"]}/MediaInfo?userId=#{player["UserId"]}",playerId).body) unless b["Path"]
    #puts b2
    p = b["Path"] || b2["MediaSources"][0]["Path"] 
    #puts "Path: #{p}"
    SendToPlayer(playerId,"QVMPF -n #{audioIndex} -l #{startAtSecs} #{p}\r")
    player[:Mode] = "play"
    player[:Time] = Time.new.to_i - startAtSecs.to_i
    player[:NowPlaying] = b
    StartProgress(playerId)
  end
  return nil
end

def Pause(playerId)
  if playerId
    player = @@playerDB[playerId]
    SendToPlayer(playerId,"QPLPAUSE\r")
    player[:Mode] = "pause"
    player[:Time] = Time.new.to_i - player[:Time].to_i - 2
    UpdateProgress(playerId)
  end
  return nil
end

def Stop(playerId)
  if playerId && @@playerDB[playerId][:NowPlaying]
    player = @@playerDB[playerId]
    StopProgress(playerId)
    SendToPlayer(playerId,"QSTOP\r")
    player[:Mode] = "stop"
    player[:NowPlaying] = nil
    player[:Time] = 0
  end
  return nil
end

#Savant Request Handling Below********************

def SavantRequest(hostname,cmd,req)
  h = Hash[req.map {|e| e.split(":") if e.to_s.include? ":"}]
  @@playerDB[hostname["address"]]||= Hash.new
  return send(cmd,hostname["address"],h)
end

def Status(playerId,req)
  player = @@playerDB[playerId]
  if player[:NowPlaying]
    if player[:NowPlaying]["RunTimeTicks"] && Time.new.to_i - player[:Time].to_i > (player[:NowPlaying]["RunTimeTicks"]) / 10000000 && player[:Mode] == "play"
      Stop(player) #Set status to stop if movie has run past duration
    else
      player[:NowPlaying]["RunTimeTicks"] ||= 0
      UpdateProgress(playerId)
      player[:Mode] == "play" ? t = Time.new.to_i - player[:Time].to_i : t = player[:Time].to_i
      d = (player[:NowPlaying]["RunTimeTicks"])/10000000
      chap = ""
      player[:NowPlaying]["Chapters"].reverse_each do |c|
        s = c["StartPositionTicks"]/10000000
        if s < t
          chap = c["Name"]
          break
        end
      end
    end  
    img = BestImage(player[:NowPlaying]["ImageTags"],player[:NowPlaying]["BackdropImageTags"])
    body = {
      :Mode => player[:Mode]||"",
      :Id => player[:NowPlaying]["Id"]||"",
      :Time => t||"",
      :Duration => d||"",
      :Info => [player[:NowPlaying]["Name"]||"",chap||"",""],
      :Artwork => "http://#{@@MovieServerAddress}/mediabrowser/Items/#{player[:NowPlaying]["Id"]}/Images/#{img}?&Format=PNG"
    }
  else
    body = {
      :Mode => "stop",
      :Id => "",
      :Time => "",
      :Duration => "",
      :Info => ["","",""],
      :Artwork => ""
    }    
  end
  return body
end

def TopMenu(playerId,req)
  puts playerId
  GetUsers(playerId) unless @@userDB.length > 0
  Login(playerId,{"id" => @@userDB[0]["Name"]}) unless @@playerDB[playerId]["UserId"]
  dat = JSON.parse(ServerGET("Users/#{@@playerDB[playerId]["UserId"]}/Views?",playerId).body)["Items"]
  b = []
  dat.each do |i|
    img = BestImage(i["ImageTags"],i["BackdropImageTags"])
    b[b.length] = {
      :id =>i["Id"],
      :cmd =>i["Type"],
      :text =>i["Name"],
      :icon =>"http://#{@@MovieServerAddress}/mediabrowser/Items/#{i["Id"]}/Images/#{img}?height=100"
      }
  end
  b[b.length] = {
    :id =>"Users",
    :cmd =>"UsersMenu",
    :text =>"Users - #{@@playerDB[playerId]["UserName"]}",
    :icon =>"http://#{@@MovieServerAddress}/mediabrowser/Users/#{@@playerDB[playerId]["UserId"]}/Images/Primary?height=100"
    }
    puts b
  return b
end

def ContextMenu(pId,req)
  mId = req["id"]
  return nil
end

def NowPlaying(pId,req)
  mId = req["id"]
  return nil
end

def AutoStart(pId,req)
  mId = req["id"]
  return nil
end

def SkipToTime(pId,req)
  t = req["time"].to_i
  Play(pId,@@playerDB[pId][:NowPlaying]["Id"],t-2,0)
  return nil
end

def TransportPlay(pId,req)
  if @@playerDB[pId][:Mode] == "pause"
    Play(pId,@@playerDB[pId][:NowPlaying]["Id"],@@playerDB[pId][:Time],0)
  end
  return nil
end

def TransportPause(pId,req)
  if @@playerDB[pId][:Mode] == "play"
    Pause(pId)
  end
  return nil
end

def TransportStop(pId,req)
  Stop(pId)
  return nil
end

def TransportFastReverse(pId,req)
  return nil
end

def TransportFastForward(pId,req)
  return nil
end

def TransportSkipReverse(pId,req)
  player = @@playerDB[pId]
  if player[:NowPlaying]
    player[:Mode] == "play" ? t = Time.new.to_i - player[:Time].to_i : t = player[:Time].to_i
    player[:NowPlaying]["Chapters"].reverse_each do |c|
      s = c["StartPositionTicks"].to_i/10000000
      if s < t -2
        Play(pId,player[:NowPlaying]["Id"],s-2,1)
        break
      end
    end
  end
  return nil
end

def TransportSkipForward(pId,req)
  player = @@playerDB[pId]
  if player[:NowPlaying]
    player[:Mode] == "play" ? t = Time.new.to_i - player[:Time].to_i : t = player[:Time].to_i
    player[:NowPlaying]["Chapters"].each do |c|
      s = c["StartPositionTicks"].to_i/10000000
      if s > t
        Play(pId,player[:NowPlaying]["Id"],s-2,1)
        break
      end
    end
  end
  return nil
end

def PowerOff(pId,req)
  mId = req["id"]
  if @@playerDB[pId][:Mode] == "play"
    Pause(pId)
  end
  return nil
end

def PowerOn(pId,req)
  mId = req["id"]
  if @@playerDB[pId][:Mode] == "pause"
    Play(pId,req["Id"],@@playerDB[pId][:Time],0)
  end
  return nil
end

def VolumeUp(pId,req)
  mId = req["id"]
  return nil
end

def VolumeDown(pId,req)
  mId = req["id"]
  return nil
end

def SetVolume(pId,req)
  mId = req["id"]
  return nil
end

def MuteOn(pId,req)
  mId = req["id"]
  return nil
end

def MuteOff(pId,req)
  mId = req["id"]
  return nil
end

#Plugin defined requests below ********************************

def Login(playerId,req)
  puts "PlayerId: #{playerId}\nReq: #{req}"
  user = req["id"]
  f = {'password'=>'da39a3ee5e6b4b0d3255bfef95601890afd80709','Username'=>user}
  res = ServerPOST("Users/authenticatebyname?",playerId,f)
  b = JSON.parse(res.body)
  #puts b.inspect
  @@playerDB[playerId]["UserId"] = b["User"]["Id"]
  @@playerDB[playerId]["UserName"] = b["User"]["Name"]
  @@playerDB[playerId]["Token"] = b["AccessToken"]
  return nil
end

def UsersMenu(playerId,req)
  mId = req["id"]
  dat = ServerGET("/Users/Public?",playerId)
  dat = JSON.parse(dat.body)
  b = []
  dat.each do |i|
    b[b.length] = {
      :id =>i["Name"],
      :cmd =>"Login",
      :text =>i["Name"],
      :icon =>"http://#{@@MovieServerAddress}/mediabrowser/Users/#{i["Id"]}/Images/Primary?height=100"
      }
  end
  return b
end

def CollectionFolder(playerId,req)
  mId = req["id"]
  dat = ServerGET("/Users/#{@@playerDB[playerId]["UserId"]}/Items?ParentId=#{mId}",playerId)
  dat = JSON.parse(dat.body)["Items"]
  b = []
  dat.each do |i|
    if i["ChildCount"] > 0
      img = BestImage(i["ImageTags"],i["BackdropImageTags"])
      b[b.length] = {
        :id =>i["Id"],
        :cmd =>i["Type"],
        :text =>i["Name"],
        :icon =>"http://#{@@MovieServerAddress}/mediabrowser/Items/#{i["Id"]}/Images/#{img}?height=100"
        }
    end
  end
  return b
end

def UserView(playerId,req)
  mId = req["id"]
  dat = ServerGET("/Users/#{@@playerDB[playerId]["UserId"]}/Items?ParentId=#{mId}",playerId)
  dat = JSON.parse(dat.body)["Items"]
  b = []
  dat.each do |i|
    if i["ChildCount"].nil? || i["ChildCount"] > 0
      img = BestImage(i["ImageTags"],i["BackdropImageTags"])
      b[b.length] = {
        :id =>i["Id"],
        :cmd =>i["Type"],
        :text =>i["Name"],
        :icon =>"http://#{@@MovieServerAddress}/mediabrowser/Items/#{i["Id"]}/Images/#{img}?height=100"
        }
    end
  end
  return b
end

def Series(playerId,req)
  mId = req["id"]
  dat = ServerGET("/Users/#{@@playerDB[playerId]["UserId"]}/Items?ParentId=#{mId}",playerId)
  dat = JSON.parse(dat.body)["Items"]
  b = []
  dat.each do |i|
    if i["ChildCount"] > 0
      img = BestImage(i["ImageTags"],i["BackdropImageTags"])
      b[b.length] = {
        :id =>i["Id"],
        :cmd =>i["Type"],
        :text =>i["Name"],
        :icon =>"http://#{@@MovieServerAddress}/mediabrowser/Items/#{i["Id"]}/Images/#{img}?height=100"
        }
    end
  end
  return b
end

def Season(playerId,req)
  mId = req["id"]
  dat = ServerGET("/Users/#{@@playerDB[playerId]["UserId"]}/Items?ParentId=#{mId}",playerId)
  dat = JSON.parse(dat.body)["Items"]
  b = []
  dat.each do |i|
    if i["ChildCount"].nil? || i["ChildCount"] > 0
      img = BestImage(i["ImageTags"],i["BackdropImageTags"])
      b[b.length] = {
        :id =>i["Id"],
        :cmd =>i["Type"],
        :text =>i["Name"],
        :icon =>"http://#{@@MovieServerAddress}/mediabrowser/Items/#{i["Id"]}/Images/#{img}?height=100"
        }
    end
  end
  return b
end

def Movie(playerId,req)
  mId = req["id"]
  dat = ServerGET("/Users/#{@@playerDB[playerId]["UserId"]}/Items?Ids=#{mId}&Fields=Chapters",playerId)
  dat = JSON.parse(dat.body)["Items"][0]["Chapters"]
  b = []
  dat.each_with_index do |i,index|
    b[b.length] = {
      :id =>"#{mId}|#{i["StartPositionTicks"] / 10000000}",
      :cmd =>"PlayAt",
      :text =>i["Name"],
      :icon =>"http://#{@@MovieServerAddress}/mediabrowser/Items/#{mId}/Images/Chapter/#{index}?height=100"
      }
  end
  Play(playerId,mId,0,0)
  return b
end

def Episode(playerId,req)
  mId = req["id"]
  dat = ServerGET("/Users/#{@@playerDB[playerId]["UserId"]}/Items?Ids=#{mId}&Fields=Chapters",playerId)
  dat = JSON.parse(dat.body)["Items"][0]["Chapters"]
  b = []
  dat.each_with_index do |i,index|
    b[b.length] = {
      :id =>"#{mId}:#{i["StartPositionTicks"] / 10000000}",
      :cmd =>"PlayAt",
      :text =>i["Name"],
      :icon =>"http://#{@@MovieServerAddress}/mediabrowser/Items/#{mId}/Images/Chapter/#{index}?height=100"
      }
  end
  Play(playerId,mId,0,0)
  return b
end

def PlayAt(playerId,req)
  
  mId = req["id"]
  mId,start = mId.split("|")
  Play(playerId,mId,start,0)
  return nil
end

end
