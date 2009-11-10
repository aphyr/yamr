#!/usr/bin/env ruby

require 'monitor'
require 'fileutils'
require 'rubygems'
require 'yammer4r'
require 'construct'
require 'gtk2'
require 'webkit'

module Yamr
  $LOAD_PATH.unshift File.dirname(__FILE__)

  require 'snippets/datetime'
  require 'snippets/gtk'
  require 'yamr/cgi'
  require 'yamr/version'
  require 'yamr/oauth'
  require 'yamr/client'
end
