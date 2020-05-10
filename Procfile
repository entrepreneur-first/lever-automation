daemon: bundle exec ruby daemon.rb start -t
console: bundle exec ruby console.rb
worker: sidekiq -t 25 -c 1 -r $PWD/worker.rb
