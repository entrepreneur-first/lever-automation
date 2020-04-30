# frozen_string_literal: true

require 'sidekiq'
require_relative 'router'

class Worker
  include Sidekiq::Worker

  def perform(command)
    Router.route(command)
  end
end
