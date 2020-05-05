# frozen_string_literal: true

require_relative 'base'
require_relative 'commands'
require_relative 'process_updates'
require_relative 'fixes'

class Controller < BaseController

  include Controller_Commands
  include Controller_ProcessUpdates
  include Controller_Fixes

end
