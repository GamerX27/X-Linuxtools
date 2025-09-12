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
  "PromosEnabled": false,

  "PasswordManagerEnabled": false,
  "CredentialProviderEnabled": false,
  "AutofillAddressEnabled": false,
  "AutofillCreditCardEnabled": false,
  "BraveRewardsDisabled": true,

  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Qwant",
  "DefaultSearchProviderSearchURL": "https://www.qwant.com/?q={searchTerms}",
  "DefaultSearchProviderSuggestURL": "https://api.qwant.com/api/suggest/?q={searchTerms}",
  "DefaultSearchProviderKeyword": "qwant",

  "DefaultGeolocationSetting": 2,
  "DefaultCameraSetting": 2,
  "DefaultMicrophoneSetting": 2,
  "DefaultNotificationsSetting": 2
}
JSON

echo "✅ Brave policies applied: make_brave_great_again.json"
