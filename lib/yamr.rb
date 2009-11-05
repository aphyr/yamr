#!/usr/bin/env ruby

require 'monitor'
require 'rubygems'
require 'yammer4r'
require 'gtk2'
require 'webkit'

module Yamr
  $LOAD_PATH.unshift File.dirname(__FILE__)

  require 'snippets/datetime'
  require 'snippets/gtk'
  require 'yamr/version'
  require 'yamr/client'
end
