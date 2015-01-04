#!/usr/bin/env ruby
#
# Sends events to Zenoss using XML-RPC.
#
# /etc/sensu/conf.d/zenoss_handler.json:
# {
#     "zenoss": {
#         "server": "localhost",
#         "port": 8081,
#         "user": "admin",
#         "password": "zenoss",
#         "device": "hostname",
#         "event_class": "/Status/Sensu"
#     }
# }
#
# Handler definitions:
# {
#     "handlers": {
#         "zenoss": {
#             "type": "pipe",
#             "command": "/etc/sensu/handlers/zenoss.rb"
#         }
#     }
# }
#
# 2014 / Miika Kankare / Cybercom Finland
#

require "rubygems" if RUBY_VERSION < "1.9.0"
require "xmlrpc/client"
require "sensu-handler"
require "timeout"

class Zenoss < Sensu::Handler
    def status_to_severity
      case @event['check']['status']
          # Resolved to Clear
          when 0
              0
          # Warning to Warning
          when 1
              3
          # Critical to Critical
          when 2
              5
          # Unknown to Critical
          else
              5
      end
    end


    def create_zenoss_event
        {
          "device"     => settings["zenoss"]["device"],
          "eventClass" => settings["zenoss"]["event_class"],
          "eventKey"   => @event["check"]["name"],
          "component"  => @event["client"]["name"],
          "summary"    => @event["check"]["output"],
          "message"    => @event,
          "severity"   => status_to_severity,
        }
    end


    def handle
        server = settings["zenoss"]["server"]
        port = settings["zenoss"]["port"]
        user = settings["zenoss"]["user"]
        password = settings["zenoss"]["password"]

        event = create_zenoss_event

        begin
            timeout(10) do
                zenoss = XMLRPC::Client.new2("http://#{user}:#{password}@#{server}:#{port}")
                zenoss.call("sendEvent", event)
            end
        rescue Timeout::Error
            puts "Connection timed out when creating event: #{event[:client][:name]} - #{event[:check][:output]}"
        end
    end
end
