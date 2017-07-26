require 'mina/rails'
require 'mina/git'
# require 'mina/rbenv'  # for rbenv support. (https://rbenv.org)
require 'mina/rvm'    # for rvm support. (https://rvm.io)

# Basic settings:
#   domain       - The hostname to SSH to.
#   deploy_to    - Path to deploy into.
#   repository   - Git repo to clone from. (needed by mina/git)
#   branch       - Branch name to deploy. (needed by mina/git)

set :application_name, 'hlbf'
set :domain, '118.190.62.74'
set :user, 'brook'
set :deploy_to, '/data/www/hlbf'
set :repository, 'git://github.com/flighting/discourse'
set :branch, 'master'
set :rails_env, 'production'
set :keep_releases, 5
set :forward_agent, true     # SSH forward_agent


# shared dirs and files will be symlinked into the app-folder by the 'deploy:link_shared_paths' step.
# set :shared_dirs, fetch(:shared_dirs, []).push('somedir')
# set :shared_files, fetch(:shared_files, []).push('config/database.yml', 'config/secrets.yml')
set :shared_dirs, fetch(:shared_dirs) + [
  'tmp',
  'public/uploads'
]

set :shared_files, [
  'config/discourse.conf',
  'config/secrets.yml'
]

# This task is the environment that is loaded for all remote run commands, such as
# `mina deploy` or `mina rake`.
task :environment do
  # If you're using rbenv, use this to load the rbenv environment.
  # Be sure to commit your .ruby-version or .rbenv-version to your repository.
  # invoke :'rbenv:load'

  # For those using RVM, use this to load an RVM version@gemset.
  invoke :'rvm:use', 'ruby-2.3.1@default'
  # invoke :'rvm:use', 'ruby-2.3.1'
end

# Put any custom commands you need to run at setup
# All paths in `shared_dirs` and `shared_paths` will be created on their own.
task :setup do
  # command %{rbenv install 2.3.0}
  command %{ mkdir -p #{fetch :shared_path}/log }
  command %{ mkdir -p #{fetch :shared_path}/config }
  command %{ mkdir -p #{fetch :shared_path}/tmp/sockets }
  command %{ mkdir -p #{fetch :shared_path}/tmp/pids }

  command %{ touch #{fetch :shared_path}/config/database.yml }
  command %{ touch #{fetch :shared_path}/config/secrets.yml }
  command %{ touch #{fetch :shared_path}/tmp/sockets/puma.state }
  command %{ touch #{fetch :shared_path}/tmp/pids/puma.pid }
  comment %{ Be sure to edit #{fetch :shared_path}/config/database.yml and secrets.yml }
end

desc "Deploys the current version to the server."
task :deploy do
  # uncomment this line to make sure you pushed your local branch to the remote origin
  # invoke :'git:ensure_pushed'
  deploy do
    # Put things that will set up an empty directory into a fully set-up
    # instance of your project.
    invoke :'git:clone'
    invoke :'deploy:link_shared_paths'
    invoke :'bundle:install'
    invoke :'rails:db_migrate'
    invoke :'rails:assets_precompile'
    invoke :'deploy:cleanup'

    on :launch do
      in_path(fetch(:current_path)) do
        command %{mkdir -p tmp/}
        command %{touch tmp/restart.txt}
      end
      invoke :'puma:restart'
      invoke :'sidekiq:restart'
    end
  end

  # you can use `run :local` to run tasks on local machine before of after the deploy scripts
  # run(:local){ say 'done' }
end


desc 'restart'
task :restart do
  command %{
    touch "#{fetch :current_path}/tmp/restart.txt"
  }
end

# For help in making your deploy script, see the Mina documentation:
#
#  - https://github.com/mina-deploy/mina/tree/master/docs
namespace :puma do
  set :puma_cmd, -> { "#{fetch :bundle_more_prefix} puma -e #{fetch :rails_env}" }
  set :pumactl_cmd, -> { "#{fetch :bundle_more_prefix} pumactl" }
  set :puma_socket, -> { "#{fetch :current_path}/tmp/pids/puma.pid" }

  desc 'Start puma'
  task start: :environment do
    in_path fetch(:current_path) do
      command "#{fetch :puma_cmd}"
    end
  end

  desc 'Stop puma'
  task stop: :environment do
    pumactl_command 'stop'
  end

  desc 'Restart puma'
  task restart: :environment do
    pumactl_command 'restart'
  end

  desc 'Restart puma (phased restart)'
  task phased_restart: :environment do
    pumactl_command 'phased-restart'
  end

  def pumactl_command(name)
    in_path fetch(:current_path) do
      command %{
        if [ -e #{fetch :puma_socket} ]
        then
          #{fetch :pumactl_cmd} #{name}
        else
          echo 'Puma is not running!';
        fi
      }
    end
  end
end


set :sidekiq, -> { "#{fetch :bundle_prefix} sidekiq -d" }
set :sidekiqctl, -> { "#{fetch :bundle_prefix} sidekiqctl" }
set :sidekiq_config, -> { "#{fetch :current_path}/config/sidekiq.yml" }
set :sidekiq_pid, -> { "#{fetch :current_path}/tmp/pids/sidekiq.pid" }
set :sidekiq_processes, 2
set :sidekiq_timeout, 10

namespace :sidekiq do

  def for_each_process(&block)
    fetch(:sidekiq_processes).times do |idx|
      if idx == 0
        pid_file = fetch :sidekiq_pid
      else
        pid_file = "#{fetch :sidekiq_pid}-#{idx}"
      end

      yield(pid_file, idx)
    end
  end

  desc 'Quiet sidekiq (stop accepting new work)'
  task quiet: :environment do
    comment 'Quiet sidekiq (stop accepting new work)'
    for_each_process do |pid_file, idx|
      command %{
        if [ -f #{pid_file} ] && kill -0 `cat #{pid_file}`> /dev/null 2>&1; then
          cd "#{deploy_to}/#{current_path}"
          #{echo_cmd %{#{sidekiqctl} quiet #{pid_file}} }
        else
          echo 'Skip quiet command (no pid file found)'
        fi
      }
    end
  end

  desc 'Stop sidekiq'
  task stop: :environment do
    comment 'Stop sidekiq'

    for_each_process do |pid_file, _|
      in_path fetch(:current_path) do
        command %{ #{fetch :sidekiqctl} stop #{pid_file} #{fetch :sidekiq_timeout}}
      end
    end
  end

  desc 'Start sidekiq'
  task start: :environment do
    comment 'Start sidekiq'

    for_each_process do |pid_file, idx|
      in_path fetch(:current_path) do
        command %{ #{fetch :sidekiq} -d -i #{idx} -P #{pid_file} }
      end
    end
  end

  desc 'run sidekiq ui'
  task :ui do
    in_path "#{fetch(:current_path)}/sidekiq" do
      command %{ #{thinctl} start -d -R sidekiq.ru -p 9292 }
    end
  end

  desc 'Restart sidekiq'
  task :restart do
    invoke :'sidekiq:stop'
    invoke :'sidekiq:start'
  end

end

