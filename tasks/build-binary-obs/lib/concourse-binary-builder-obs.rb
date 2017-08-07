require 'yaml'
require 'digest'
require 'fileutils'
require 'net/http'
require 'open-uri'
require 'uri'
require_relative '../../../lib/git-client'
require_relative '../../../lib/concourse-binary-builder'
require_relative 'obs_binary_builder'

class ConcourseBinaryBuilderObs < ConcourseBinaryBuilder
  def trigger
    load_builds_yaml

    unless latest_build
      puts "There are no new builds for #{dependency} requested."
      exit
    end

    build_dependency
  end

  def process
    # There is currently no notification hook which would allow for triggering
    # jobs in concourse whenever an OBS build is published. As a workaround we
    # poll the mirror for the expected file for 60 minutes at most.
    # This polling should be removed when OBS added the needed hook.
    wait_for_mirror_publish

    fetch_package_from_mirror

    add_md5_to_binary_name

    copy_binaries_to_output_directory

    create_git_commit_msg

    commit_yaml_artifacts
  end

  private

  def build_dependency
    builder = ObsBinaryBuilder.new(dependency, latest_build["version"])
    @source_url = builder.source_url
    builder.build
  end

  def fetch_package_from_mirror
    File.write("#{binary_builder_dir}/#{dependency}-#{latest_build["version"]}.tgz", open(get_package_url).read)
  end

  def get_package_url
    obs_project = ENV["OBS_PROJECT"] || raise("no OBS_PROJECT environment variable set")
    URI("http://download.opensuse.org/repositories/#{obs_project.gsub(":", ":/")}/openSUSE_Leap_42.3/cf-buildpack-binary-#{dependency}-#{latest_build["version"]}.tgz")
  end

  def wait_for_mirror_publish
    url = get_package_url
    60.times do |i|
      result = nil
      Net::HTTP.start(url.host, url.port) do |http|
        result = http.head(url.path)
      end
      puts "Checking #{i+1}/60 for tarball to be published under #{url}...#{result.code}"
      break if result.kind_of?(Net::HTTPSuccess) || result.kind_of?(Net::HTTPFound)

      sleep(60)
    end
  end
end
