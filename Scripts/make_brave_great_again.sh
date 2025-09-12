#!/bin/bash
# make_brave_great_again.sh
# Disable unwanted Brave features via managed policy
#the name has nothing to do with politics even if it sounds like it...

# Stop on errors
set -e

# Create the policies directory if it doesn't exist
sudo mkdir -p /etc/brave/policies/managed

# Write the policy JSON
sudo tee /etc/brave/policies/managed/make_brave_great_again.json >/dev/null <<'JSON'
{
  "BraveAIChatEnabled": false,
  "BraveWalletDisabled": true,
  "BraveCryptoWalletsEnabled": false,
  "IPFSDisabled": true,
  "TorDisabled": true,

  "BraveP3AEnabled": false,
  "BraveAdsDataCollectionEnabled": false,
  "BraveReferralHeadersEnabled": false,
  "MetricsReportingEnabled": false,
  "BackgroundModeEnabled": false,
  "SafeBrowsingExtendedReportingEnabled": false,
  "SpellcheckUseSpellingService": false,
  "UrlKeyedAnonymizedDataCollectionEnabled": false,
  "DefaultBrowserSettingEnabled": false,
  "PromosEnabled": false
}
JSON

echo "✅ Brave policies applied: make_brave_great_again.json"
