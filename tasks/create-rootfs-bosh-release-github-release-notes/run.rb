#!/usr/bin/env ruby

if ENV.fetch('ROOTFS_TYPE') == 'nc'
  repo = 'pivotal-cf/cflinusfs2-nc'
else
  repo = 'cloudfoundry/cflinuxfs2'
end

body_file = 'release-body/body'
version = `cat version/number`
github_url = "https://github.com/#{repo}/releases/tag/#{version}"

message = "This release ships with #{repo.split('/').last} version #{version}. For more information, see the [release notes](#{github_url})"

File.write(body_file, message)
