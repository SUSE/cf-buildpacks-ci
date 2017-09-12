#!/usr/bin/env ruby

require 'tempfile'
require 'erb'
require 'uri'
require 'open-uri'
require 'yaml'

class ObsBinaryBuilder
  attr_accessor :binary, :version

  TEMPLATE_PATH = File.join(File.dirname(__FILE__), "../templates")

  def initialize(binary, version, extensions_dir)
    @binary = binary
    @version = version
    @extensions_dir = extensions_dir
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

  def extension_urls
    extensions_file = File.join(@extensions_dir, "#{@binary}-extensions.yml")
    return [] if !File.exists?(extensions_file)

    puts "Extensions file #{extensions_file} found"
    extensions = YAML.load_file(extensions_file)

    extensions.values.flatten.map { |extension| extension_url(extension) }.compact
  end

  def extension_url(extension)
    version = extension["version"]
    name = extension["name"]

    case extension["klass"]
    when "PeclRecipe", "AmqpPeclRecipe", "GeoipRecipe", "OraclePeclRecipe", "MemcachedPeclRecipe", "LuaPeclRecipe"
      "http://pecl.php.net/get/#{name}-#{version}.tgz"
    when "HiredisRecipe"
      "https://github.com/redis/hiredis/archive/v#{version}.tar.gz"
    when "IonCubeRecipe"
      "http://downloads3.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64_#{version}.tar.gz"
    when "LibmemcachedRecipe"
      "https://launchpad.net/libmemcached/1.0/#{version}/+download/libmemcached-#{version}.tar.gz"
    when "UnixOdbcRecipe"
      "http://www.unixodbc.org/unixODBC-#{version}.tar.gz"
    when "LibRdKafkaRecipe"
      "https://github.com/edenhill/librdkafka/archive/v#{version}.tar.gz"
    when "CassandraCppDriverRecipe"
      "https://github.com/datastax/cpp-driver/archive/#{version}.tar.gz"
    when "LuaRecipe"
      "http://www.lua.org/ftp/lua-#{version}.tar.gz"
    when "RabbitMQRecipe"
      "https://github.com/alanxz/rabbitmq-c/archive/v#{version}.tar.gz"
    when "PhalconRecipe"
      "https://github.com/phalcon/cphalcon/archive/v#{version}.tar.gz"
    when "PHPIRedisRecipe"
      "https://github.com/nrk/phpiredis/archive/v#{version}.tar.gz"
    when "PHPProtobufPeclRecipe"
     "https://github.com/allegro/php-protobuf/archive/v#{version}.tar.gz"
    when "SuhosinPeclRecipe"
      "https://download.suhosin.org/suhosin-#{version}.tar.gz"
    when "TwigPeclRecipe"
      "https://github.com/twigphp/Twig/archive/v#{version}.tar.gz"
    when "XcachePeclRecipe"
      "http://xcache.lighttpd.net/pub/Releases/#{version}/xcache-#{version}.tar.gz"
    when "XhprofPeclRecipe"
      "https://github.com/phacility/xhprof/archive/#{version}.tar.gz"
    when "SnmpRecipe", "OraclePdoRecipe"
      # Nothing to download here
      nil
    else
      raise "URL for #{extension} not found"
    end
  end

  def source_urls
    urls = case @binary
    when 'bundler'
      "http://rubygems.org/gems/#{@binary}-#{@version}.gem"
    when 'ruby'
      "https://cache.ruby-lang.org/pub/ruby/#{minor_version}/ruby-#{@version}.tar.gz"
    when 'go'
      "https://storage.googleapis.com/golang/go#{@version}.src.tar.gz"
    when 'python'
      "https://www.python.org/ftp/python/#{version}/Python-#{version}.tgz"
    when 'jruby'
      jruby_version = version.match(/(.*)_ruby-\d+\.\d.*/)[1]
      "https://s3.amazonaws.com/jruby.org/downloads/#{jruby_version}/jruby-src-#{jruby_version}.tar.gz"
    when 'php', 'php7'
      "https://php.net/distributions/php-#{version}.tar.gz"
    when 'httpd'
      [
        "http://apache.mirrors.tds.net/apr/apr-1.6.2.tar.gz",
        "http://apache.mirrors.tds.net/apr/apr-iconv-1.2.1.tar.gz",
        "http://apache.mirrors.tds.net/apr/apr-util-1.6.0.tar.gz",
        "https://archive.apache.org/dist/httpd/httpd-#{version}.tar.bz2"
      ]
    end
    Array(urls) + extension_urls
  end

  private

  def package_string
    "#{@binary}-#{@version}"
  end

  def fetch_sources
    source_urls.each do |url|
      puts "Downloading #{url}..."
      filename = File.basename(URI.parse(url).path)
      puts " -> #{filename}"
      File.write(filename, open(url).read)
    end
  end

  def spec_sources
    source_urls.each_with_index.map do |url, index|
      "Source#{index}: #{url}"
    end.join("\n")
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
