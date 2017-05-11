require_relative 'buildpacks-ci-configuration'

class BuildpacksCIPipelineUpdateCommand
  def run!(concourse_target_name:, pipeline_name:, config_generation_command:, pipeline_variable_filename: "", options:)

    buildpacks_configuration = BuildpacksCIConfiguration.new

    pipeline_prefix = ENV.fetch('PIPELINE_PREFIX', '')

    text_to_include = options[:include]
    text_to_exclude = options[:exclude]
    return if options.has_key?(:include) && !pipeline_name.include?(text_to_include)
    return if options.has_key?(:exclude) && pipeline_name.include?(text_to_exclude)

    puts "   #{pipeline_name} pipeline"

    pipeline_specific_config = ""
    pipeline_specific_config ="--load-vars-from=#{pipeline_variable_filename}" unless pipeline_variable_filename.empty?
    fly_cmd = %{bash -c "fly \
      --target=#{concourse_target_name} \
      set-pipeline \
      --pipeline=#{pipeline_prefix}#{pipeline_name} \
      --config=<(#{config_generation_command}) \
      --load-vars-from=<(gpg -d --no-tty ../cloudfoundry/secure/concourse-secrets.yml.gpg 2> /dev/null; cat secrets-map.yaml) \
      --load-vars-from=public-config.yml \
    #{pipeline_specific_config}
    "}

    system "#{fly_cmd}"
  end
end
