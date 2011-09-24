require 'rubygems'
['dj9'].each { |req| require "#{File.dirname(__FILE__)}/#{req}" }

# Kick off the back, then kick off the front
Mc9.run!
Dj9.run!