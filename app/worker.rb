# frozen_string_literal: true

require 'sidekiq'
require_relative 'router'

class Worker
  include Sidekiq::Worker
  sidekiq_options queue: ENV['APP_ENV'] || 'test'

  def perform(command)
    Router.route(command)
  end
end
