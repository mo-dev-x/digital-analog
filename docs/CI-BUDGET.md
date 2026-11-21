# Hosted CI controls

The workflow is opt-in only: it has no push or pull-request triggers, and both runner jobs have an explicit false condition. Uploading or committing this source does not enable those jobs. Manual dispatch also skips them until the guards are deliberately changed.

Before enabling hosted validation, check runner pricing, included allowance, account budgets, and any overage controls. Repository workflow settings do not enforce an account-wide spending limit. Batch native checks when possible and cancel superseded runs.

Local development and compatible tests can continue with Actions disabled. Linux and Windows do not provide Xcode or Apple's iOS Simulator. An unsigned CI-generated IPA still requires signing before installation.
