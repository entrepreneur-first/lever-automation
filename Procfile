daemon: bundle exec ruby daemon.rb start -t
daemon_active: bundle exec ruby daemon.rb start -t active
daemon_current_cohorts: bundle exec ruby daemon.rb start -t current_cohorts
console: bundle exec ruby console.rb
worker: sidekiq -q $APP_ENV -t 25 -c 1 -r $PWD/worker.rb
