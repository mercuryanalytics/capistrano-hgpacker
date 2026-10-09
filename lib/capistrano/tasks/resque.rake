# frozen_string_literal: true

require "shellwords"

namespace :hgpacker do
  namespace :resque do
    # Age against the last cutover, not count: a deploy's new manager INTs the old
    # one, which exits without waiting, so long jobs drain in orphaned workers
    # whose proclines drop the master prefix. A master older than the cutover
    # escaped that INT, or is blocked in a QUIT drain that cannot process one. The
    # doubled backslashes survive the heredoc, so pgrep gets the brackets — and
    # they keep the pattern from matching the shell delivering this script.
    #
    # Both halves lean on the gem's resque-pool@.service: its `ExecReload` re-runs
    # `resque-pool-app %i up`, whose `-k` is what INTs the older managers, and the
    # `-a %i` that wrapper passes is what puts the app name in the brackets. An
    # `ExecReload` that HUPs instead blocks every deploy after the first; a dropped
    # `-a %i` makes this pattern match nothing, and the check then passes forever
    # without saying so.
    def hgpacker_stale_master_script(release_link, app)
      <<~SH
        set -e
        link="#{release_link}"
        [ -L "$link" ] || [ -e "$link" ] || exit 0
        cutover=$(stat -c %Y "$link")
        deployed=$(( $(date +%s) - cutover ))
        for pid in $(pgrep -f "resque-pool-master\\[#{app}\\]" || true); do
          elapsed=$(ps -o etimes= -p "$pid" | tr -d ' ' || true)
          if [ "${elapsed:-0}" -gt "$deployed" ]; then echo "$pid"; fi
        done
      SH
    end

    desc "Fail the deploy if a resque master survived the previous deploy"
    task :check_stale do
      script = hgpacker_stale_master_script(current_path, fetch(:application)).shellescape

      on roles(:resque) do
        stale = capture(:bash, "-c", script).split

        next if stale.empty?

        error "Stale resque-pool master(s) on #{host}: #{stale.join(', ')}"
        error "They are running retired code and will destroy jobs once their release is pruned."
        error "Retire them with: sudo kill -INT #{stale.join(' ')}"
        error "One left draining by `systemctl stop` ignores INT; kill -9 it, its workers already have their QUIT."
        raise "resque-pool master #{stale.join(', ')} survived the previous deploy"
      end
    end
  end
end

before :deploy, "hgpacker:resque:check_stale"
