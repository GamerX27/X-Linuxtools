#!/bin/bash
# make_brave_great_again.sh
# Disable unwanted Brave features via managed policy
#the name has nothing to do with politics even if it sounds like it...

set -e

sudo mkdir -p /etc/brave/policies/managed

sudo tee /etc/brave/policies/managed/make_brave_great_again.json >/dev/null <<'JSON'
{
  "BraveAIChatEnabled": false,
  "BraveWalletDisabled": true,
  "TorDisabled": true,
  "BraveRewardsDisabled": true,

  "BraveP3AEnabled": false,
  "BraveStatsPingEnabled": false,
  "BraveWebDiscoveryEnabled": false,

  "MetricsReportingEnabled": false,
  "BackgroundModeEnabled": false,
  "SafeBrowsingExtendedReportingEnabled": false,
  "UrlKeyedAnonymizedDataCollectionEnabled": false,
  "DefaultBrowserSettingEnabled": false,
  "PromotionsEnabled": false,

  "PasswordManagerEnabled": false,
  "AutofillAddressEnabled": false,
  "AutofillCreditCardEnabled": false,

  "SpellCheckServiceEnabled": false,
  "SpellcheckEnabled": true,

  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Qwant",
  "DefaultSearchProviderSearchURL": "https://www.qwant.com/?q={searchTerms}",
  "DefaultSearchProviderSuggestURL": "https://api.qwant.com/v3/suggest?q={searchTerms}",

  "BraveVPNDisabled": true,
  "BraveNewsDisabled": true,
  "BraveTalkDisabled": true
}
JSON

echo "✅ Brave policies applied: make_brave_great_again.json"
