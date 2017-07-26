if ENV['RAILS_ENV']=='production'
  #!/usr/bin/env puma

  #rails的运行环境
  environment 'production'
  threads 2, 32
  workers 1

  #项目名
  app_name = "hlbf"
  #项目路径
  application_path = "/data/www/#{app_name}"
  #这里一定要配置为项目路径下地current
  directory "#{application_path}/current"

  #下面都是 puma的配置项
  pidfile "#{application_path}/shared/tmp/pids/puma.pid"
  state_path "#{application_path}/shared/tmp/sockets/puma.state"
  stdout_redirect "#{application_path}/shared/log/puma.stdout.log", "#{application_path}/shared/log/puma.stderr.log"
  bind "unix://#{application_path}/shared/tmp/sockets/#{app_name}.sock"
  activate_control_app "unix://#{application_path}/shared/tmp/sockets/pumactl.sock"

  #后台运行
  daemonize true
  on_restart do
    puts 'On restart...'
  end
  preload_app!




  # # First, you need to change these below to your situation.
  # APP_ROOT = '/data/www/hlbf/current'
  # num_workers = 1 # ENV["NUM_WEBS"].to_i > 0 ? ENV["NUM_WEBS"].to_i : 4

  # # Second, you can choose how many threads that you are going to run at same time.
  # workers "#{num_workers}"
  # threads 8,32

  # # Unless you know what you are changing, do not change them.
  # bind  "unix://#{APP_ROOT}/tmp/sockets/puma.sock"
  # stdout_redirect "#{APP_ROOT}/log/puma.log","#{APP_ROOT}/log/puma.err.log"
  # pidfile "#{APP_ROOT}/tmp/pids/puma.pid"
  # state_path "#{APP_ROOT}/tmp/pids/puma.state"
  # daemonize true
  # preload_app!

end


