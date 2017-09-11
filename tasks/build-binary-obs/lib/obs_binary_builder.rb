#!/usr/bin/env ruby

require 'tempfile'
require 'erb'
require 'uri'
require 'open-uri'

class ObsBinaryBuilder
  attr_accessor :binary, :version

  TEMPLATE_PATH = File.join(File.dirname(__FILE__), "../templates")

  def initialize(binary, version)
    @binary = binary
    @version = version
  end

  def build
    puts 'Create the package on OBS using "osc"'
    create_obs_package

    puts 'Checkout the package with osc'
    checkout_obs_package

    puts 'Change working directory'
    Dir.chdir("#{obs_project}/#{package_string}")

    puts 'Download the source and put them in the package dir'
    fetch_sources

    puts 'Render the spec template and put it in the package dir'
    render_spec_template

    puts 'Commit the changes on OBS'
    commit_obs_package

    puts 'Done!'
  end

  def source_url
    case @binary
    when 'bundler'
      "http://rubygems.org/gems/#{@binary}-#{@version}.gem"
    when 'ruby'
      "https://cache.ruby-lang.org/pub/ruby/#{minor_version}/ruby-#{@version}.tar.gz"
    when 'go'
      "https://storage.googleapis.com/golang/go#{@version}.src.tar.gz"
    when 'python'
      "https://www.python.org/ftp/python/#{version}/Python-#{version}.tgz"
    when 'php', 'php7'
      "https://php.net/distributions/php-#{version}.tar.gz"
    end
  end

  private

  def package_string
    "#{@binary}-#{@version}"
  end

  def fetch_sources
    File.write(source_filename, open(source_url).read)
  end

  def source_filename
    File.basename(URI.parse(source_url).path)
  end

  def create_obs_package
    package_meta_template = <<EOF
<package project="#{obs_project}" name="#{package_string}">
  <title>#{package_string}</title>
  <description>
    Automatic build of #{package_string} @binary for the use in buildpacks in SUSE CAP.
  </description>
</package>
EOF

    Tempfile.open("package_meta_template") do |file|
      file.write(package_meta_template)
      file.close

      run_command("osc meta pkg #{obs_project} #{package_string} -F #{file.path}")
    end
  end

  def checkout_obs_package
    run_command("osc checkout #{obs_project}/#{package_string}", allowed_exit_codes: [1])
  end

  def render_spec_template
    spec_template = File.read("#{TEMPLATE_PATH}/#{@binary}.spec.erb")
    result = ERB.new(spec_template).result(binding)
    File.write("#{@binary}.spec", result)

    if File.exists?("#{TEMPLATE_PATH}/rpmlintrc.#{@binary}")
      FileUtils.cp("#{TEMPLATE_PATH}/rpmlintrc.#{@binary}", "rpmlintrc")
    end
  end

  def commit_obs_package
    run_command("osc addremove")
    run_command("osc commit -m 'Commiting files'")
  end

  def minor_version
    @version.match(/(\d+\.\d+)\./)[1]
  end

  def obs_project
    ENV["OBS_PROJECT"] || raise("no OBS_PROJECT environment variable set")
  end

  def prefix_path
    "/app/vendor/#{@binary}-#{@version}"
  end

  def run_command(command, allowed_exit_codes: [])
    `#{command}`
    if !$?.success? && !allowed_exit_codes.include?($?.exitstatus)
      STDERR.puts "Command '#{command}' has failed with exit status #{$?.exitstatus}"
      exit 1
    end
  end
end
