#!/usr/bin/env ruby
# encoding: utf-8

# Setup .oscrc
oscrc_path = "/root/.oscrc"
File.write(oscrc_path,
  File.read(oscrc_path).sub("<username>", ENV["OBS_USERNAME"]).sub("<password>", ENV["OBS_PASSWORD"])
)

task_root_dir = File.expand_path(File.join(File.dirname(__FILE__), '..','..', '..'))

require_relative "lib/concourse-binary-builder-obs"

binary_builder = ConcourseBinaryBuilderObs.new(ENV.fetch('DEPENDENCY'), task_root_dir, ENV.fetch('GIT_SSH_KEY'), ENV.fetch('BINARY_BUILDER_PLATFORM'), ENV.fetch('BINARY_BUILDER_OS_NAME'))

binary_builder.trigger
binary_builder.process
