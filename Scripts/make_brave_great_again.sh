#!/bin/bash
# make_brave_great_again.sh
# Disable unwanted Brave features via managed policy
# The name has nothing to do with politics even if it sounds like it...
# It may say in the privacy settings the mic and camera are still on, but they are blocked from being accessed.
set -e

# ---- Detect Brave Flatpak & scope (system/user) ----
has_brave_flatpak() {
  command -v flatpak >/dev/null 2>&1 && flatpak info com.brave.Browser >/dev/null 2>&1
}
brave_flatpak_scope() {
  # returns "system" or "user"
  flatpak info com.brave.Browser 2>/dev/null | awk -F': *' '/^Installation:/ {print tolower($2)}'
}
# ----------------------------------------------------

# Create the policies dir and write the policy file
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
  "BraveTalkDisabled": true,

  "DefaultGeolocationSetting": 2,
  "DefaultNotificationsSetting": 2,
  "VideoCaptureAllowed": false,
  "AudioCaptureAllowed": false,

  "DefaultJavaScriptOptimizerSetting": 2,
  "ChromeVariations": 2,
  "DefaultSensorsSetting": 2,
  "SafeBrowsingProxiedRealTimeChecksAllowed": false,
  "SafeBrowsingProtectionLevel": 0,
  "DefaultPopupsSetting": 2,
  "ChromeVariations": 2,
  "URLBlocklist": [
   "https://variations.brave.com/*",
   "https://safebrowsing.brave.com/*"
  ]
}
JSON

echo "Brave policies written: /etc/brave/policies/managed/make_brave_great_again.json"

# If Brave is the Flatpak, grant it read-only access to the policies dir
if has_brave_flatpak; then
  scope="$(brave_flatpak_scope)"
  if [ "$scope" = "system" ]; then
    echo "Detected Brave (Flatpak, system install) — applying filesystem override..."
    sudo flatpak override --system com.brave.Browser --filesystem=/etc/brave/policies/managed:ro
  else
    echo "Detected Brave (Flatpak, user install) — applying filesystem override..."
    flatpak override --user com.brave.Browser --filesystem=/etc/brave/policies/managed:ro
  fi
  echo "Flatpak override applied."
else
  echo "Brave Flatpak not detected — no Flatpak override needed."
fi

# ---- Block Brave telemetry domains in /etc/hosts (last step) ----
if ! grep -q "variations.brave.com" /etc/hosts; then
  echo "Adding variations.brave.com to /etc/hosts..."
  echo -e "0.0.0.0 variations.brave.com\n:: variations.brave.com" | sudo tee -a /etc/hosts >/dev/null
  echo "variations.brave.com entries added."
else
  echo "variations.brave.com already exists in /etc/hosts. Skipping."
fi

if ! grep -q "safebrowsing.brave.com" /etc/hosts; then
  echo "Adding safebrowsing.brave.com to /etc/hosts..."
  echo -e "0.0.0.0 safebrowsing.brave.com\n:: safebrowsing.brave.com" | sudo tee -a /etc/hosts >/dev/null
  echo "safebrowsing.brave.com entries added."
else
  echo "safebrowsing.brave.com already exists in /etc/hosts. Skipping."
fi
# -----------------------------------------------------

echo "All done."

# Credits
# Chromium Policy: https://chromeenterprise.google/policies/
# Brave Policy: https://support.brave.app/hc/en-us/articles/360039248271-Group-Policy
