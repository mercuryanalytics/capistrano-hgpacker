# frozen_string_literal: true

namespace :deploy do
  task :restart do
    on roles(:web), in: :sequence, wait: 5 do
      execute "sudo /bin/systemctl restart passenger@#{fetch(:application)}"
    end
  end

  after :publishing, :restart
end
