# lms-lmq
Savant LMQ injector

##Extremely experimental. More info coming soon.

###General Setup

####Blueprint

Script must run on same LAN as the Savant System and have port 9000 available to work properly.

Each Plugin is at differing levels of 'completeness'

The following profile can be imported into your blueprint config and connected to Video, Audio, and Network.
https://raw.githubusercontent.com/benumc/lms-lmq/master/lmq_movieplayer.xml
You need to use 1 movieplayer.xml in your project for each plugin and each streaming device (starting with 1 is a good idea)

The Host Address on the wire of the component needs to be the IP address of the device that is running the LMSLMQ script.

The hostname field of movieplayer is setup a bit differently depending on the plugin.

The general format is ```plugin:<name-of-plugin>,address:<ip-address-of-actual-player>:<control-port-of-player>```

If the device relies on a server like plex, you may need to add ```,server:<ip-of-server>:<control-port-of-server>```

By default Plex uses port 3005 for Plex Home Theater players and 32400 for the server.

####Script
To keep things as simple as possible, download the entire zip 
https://github.com/benumc/lms-lmq/archive/master.zip 
and extract it to the folder that you would like to run it from.

While testing, you can open a terminal window and run the script using ```ruby LMSLMQ.rb```
Trying to run the plugins directly won't work. LMSLMQ acts as a bridge between the savant system and whatever plugin you are using.
