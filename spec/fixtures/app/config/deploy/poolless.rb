# frozen_string_literal: true

# A resque host whose app removed the resque pool service.
server "aws0", user: "deployer", roles: %w[resque]

set :hgpacker_services, -> { { "resque-pool@#{fetch(:application)}" => nil } }
