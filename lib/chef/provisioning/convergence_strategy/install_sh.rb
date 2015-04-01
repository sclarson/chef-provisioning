require 'chef/provisioning/convergence_strategy/precreate_chef_objects'
require 'pathname'

class Chef
module Provisioning
  class ConvergenceStrategy
    class InstallSh < PrecreateChefObjects
      @@install_sh_cache = {}

      def initialize(convergence_options, config)
        super
        @install_sh_url = convergence_options[:install_sh_url] || 'https://www.chef.io/chef/install.sh'
        @install_sh_path = convergence_options[:install_sh_path] || '/tmp/chef-install.sh'
        @chef_version = convergence_options[:chef_version]
        @prerelease = convergence_options[:prerelease]
        @install_sh_arguments = convergence_options[:install_sh_arguments]
        @bootstrap_env = convergence_options[:bootstrap_proxy] ? "http_proxy=#{convergence_options[:bootstrap_proxy]} https_proxy=$http_proxy " : ""
        @chef_client_timeout = convergence_options.has_key?(:chef_client_timeout) ? convergence_options[:chef_client_timeout] : 120*60 # Default: 2 hours
      end

      attr_reader :chef_version
      attr_reader :prerelease
      attr_reader :install_sh_url
      attr_reader :install_sh_path
      attr_reader :install_sh_arguments
      attr_reader :bootstrap_env

      def install_sh_command_line
        arguments = install_sh_arguments ? " #{install_sh_arguments}" : ""
        arguments << " -v #{chef_version}" if chef_version
        arguments << " -p" if prerelease
        "bash -c '#{bootstrap_env} bash #{install_sh_path}#{arguments}'"
      end

      def setup_convergence(action_handler, machine)
        super

        # Check for existing chef client.
        version = machine.execute_always('chef-client -v')

        # Don't do install/upgrade if a chef client exists and
        # no chef version is defined by user configs or
        # the chef client's version already matches user config
        if version.exitstatus == 0
          version = version.stdout.strip
          if !chef_version
            return
          # This logic doesn't cover the case for a client with 12.0.1.dev.0 => 12.0.1
          # so we decided to just use exact version for the time being (see comments in PR 303)
          #elsif version.stdout.strip =~ /Chef: #{chef_version}([^0-9]|$)/
          elsif version =~ /Chef: #{chef_version}$/
            Chef::Log.debug "Already installed chef version #{version}"
            return
          elsif version.include?(chef_version)
            Chef::Log.warn "Installed chef version #{version} contains desired version #{chef_version}.  " +
              "If you see this message on consecutive chef runs tighten your desired version constraint to prevent " +
              "multiple convergence."
          end
        end

        # Install chef client
        # TODO ssh verification of install.sh before running arbtrary code would be nice?
        @@install_sh_cache[install_sh_url] ||= Net::HTTP.get(URI(install_sh_url))
        machine.write_file(action_handler, install_sh_path, @@install_sh_cache[install_sh_url], :ensure_dir => true)
        # TODO handle bad version case better
        machine.execute(action_handler, install_sh_command_line)
      end
    end
  end
end
end
