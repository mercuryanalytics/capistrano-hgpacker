# frozen_string_literal: true

namespace :load do
  task :defaults do
    set :required_packages, []

    set :logrotate_conf_path, -> { File.join("/etc", "logrotate.d", "#{fetch(:application)}_#{fetch(:stage)}") }

    set :cloudwatch_agent_user, :ubuntu
    set :cloudwatch_file_path, shared_path.join("log/#{fetch(:stage)}.json")
    set :cloudwatch_group_name, "workbench_#{fetch(:stage)}.json"
    set :cloudwatch_stream_name, "{instance_id}"
    set :cloudwatch_conf_path, -> { File.join("/opt", "aws", "amazon-cloudwatch-agent", "etc", "amazon-cloudwatch-agent.d", "#{fetch(:application)}_#{fetch(:stage)}.json") }
  end
end

namespace :hgpacker do
  def passenger_path
    deploy_path.join(fetch(:passenger_path, "passenger"))
  end

  def credentials_path
    shared_path.join(fetch(:credentials_path, "config/credentials"))
  end

  namespace :check do
    task :directories do
      on release_roles :app do
        execute :mkdir, "-p", passenger_path, credentials_path
      end
    end
  end

  desc "Install application keys from Secrets Manager"
  task :keys do
    invoke "hgpacker:keys:credentials"
    invoke "hgpacker:keys:google_translate"
  end

  namespace :keys do
    desc "Install credentials key from Secrets Manager"
    task :credentials do
      rails_env = fetch(:rails_env)
      key_id = "#{fetch(:application)}/credentials/production"
      key_file = credentials_path.join("#{rails_env}.key")
      on release_roles :app do
        execute :aws, :secretsmanager, "get-secret-value",
                "--secret-id", key_id,
                "|", :jq, "-r", "'.SecretString|fromjson.#{rails_env}'",
                ">", key_file
      end
    end

    desc "Install Google Translate key from Secrets Manager"
    task :google_translate do
      key_id = "#{fetch(:application)}/credentials/google-translate"
      key_file = credentials_path.join("translate-credentials.json")
      on release_roles :app do
        execute :aws, :secretsmanager, "get-secret-value",
                "--secret-id", key_id,
                "|", :jq, "-r", "'.SecretString|fromjson'",
                ">", key_file
      end
    end
  end

  desc "Install debian packages required by the application"
  task :required_packages do
    packages = fetch(:required_packages)
    next if packages.empty?

    on release_roles :app do
      sudo :"apt-get", :install, "-y", *packages
    end
  end

  desc "Configure log managment"
  task :logs do
    invoke "hgpacker:logs:logrotate"
    invoke "hgpacker:logs:cloudwatch_agent"
  end

  namespace :logs do
    desc "Configure logrotate"
    task :logrotate do
      tmp = "logrotate-#{SecureRandom.hex(10)}.conf"
      on release_roles :app do
        contents = <<~CONFIG
          #{shared_path.join('log/*.log')} {
            su deployer deployer
            daily
            missingok
            rotate 7
            compress
            delaycompress
            notifempty
            copytruncate
          }

          #{shared_path.join('log/*.json')} {
              su deployer deployer
              weekly
              missingok
              rotate 52
              compress
              delaycompress
              notifempty
              copytruncate
          }
        CONFIG

        upload! StringIO.new(contents), tmp
        sudo :mv, tmp, fetch(:logrotate_conf_path)
        sudo :chown, "root:", fetch(:logrotate_conf_path)
      end
    end

    task :cloudwatch_agent do
      tmp = "cloudwatch-#{SecureRandom.hex(10)}.json"
      on release_roles :app do
        contents = {
          agent: {
            run_as_user: fetch(:cloudwatch_agent_user)
          },
          logs: {
            logs_collected: {
              files: {
                collect_list: [
                  {
                    file_path: fetch(:cloudwatch_file_path),
                    log_group_name: fetch(:cloudwatch_group_name),
                    log_stream_name: fetch(:cloudwatch_stream_name)
                  }
                ]
              }
            }
          }
        }

        upload! StringIO.new(JSON.pretty_generate(contents)), tmp
        sudo :mv, tmp, fetch(:cloudwatch_conf_path)
        sudo :chown, "#{fetch(:cloudwatch_agent_user)}:", fetch(:cloudwatch_conf_path)
      end
    end
  end
end
