# frozen_string_literal: true

# An app that sets nothing: only the gem's defaults apply.
server "web0", user: "deployer", roles: %w[web app db]
