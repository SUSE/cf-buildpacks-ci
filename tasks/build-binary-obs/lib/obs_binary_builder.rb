#!/usr/bin/env ruby

require 'tempfile'
require 'erb'
require 'uri'

class ObsBinaryBuilder
  attr_accessor :binary, :version

  TEMPLATE_PATH = File.join(File.dirname(__FILE__), "../templates")

  def initialize(binary, version)
    @binary = binary
    @version = version
  end

  def build
    package_string = "#{@binary}-#{@version}"

    puts 'Create the package on OBS using "osc"'
    create_obs_package(package_string)

    puts 'Checkout the package with osc'
    checkout_obs_package(package_string)

    puts 'Removing obsolete old packages'
    remove_obsolete_file_from_obs_project(package_string)

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
    end
  end

  private

  def fetch_sources
    run_command("wget #{source_url}")
  end

  def create_obs_package(package_name)
    package_meta_template = <<EOF
<package project="#{obs_project}" name="#{package_name}">
  <title>#{package_name}</title>
  <description>
    Automatic build of #{package_name} @binary for the use in buildpacks in SCF.
  </description>
</package>
EOF

    Tempfile.open("package_meta_template") do |file|
      file.write(package_meta_template)
      file.close

      run_command("osc meta pkg #{obs_project} #{package_name} -F #{file.path}")
    end
  end

  def checkout_obs_package(package_name)
    run_command("osc checkout #{obs_project}/#{package_name}", allowed_exit_codes: [1])
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

  def remove_obsolete_file_from_obs_project(package_string)
    obs_package_file_path = File.join(obs_project, package_string, File.basename(URI.parse(source_url).path))
    if File.exists?(obs_package_file_path)
      File.delete(obs_package_file_path)
    else
      puts "Nothing to delete, #{obs_package_file_path} does not exist."
    end
  end

  def run_command(command, allowed_exit_codes: [])
    process_output = `#{command}`
    if !$?.success? && !allowed_exit_codes.include?($?.exitstatus)
      STDERR.puts "Command '#{command}' has failed with exit status #{$?.exitstatus}"
      exit 1
    end
  end
end
