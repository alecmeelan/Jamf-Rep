#!/bin/bash
#
# Script Name: mobile_device_app_scopes.sh
# Description: This script retrieves the scope details of mobile device applications from Jamf Pro 
#              and exports them to a CSV file.
# Created On: 2025-02-10
# Last Modified: 2025-02-10
# Author: Alec Meelan
#

# Prompt for subdomain, username, password, and file path
read -p "Enter your Jamf Cloud subdomain (e.g., 'yourcompany' for 'yourcompany.jamfcloud.com'): " subdomain
read -p "Enter your Jamf username: " username
read -s -p "Enter your Jamf password: " password
echo

# Set the Jamf URL based on the subdomain
url="https://${subdomain}.jamfcloud.com"

# Default file path to the user's Documents folder
defaultFilePath="${HOME}/Documents/mobile_device_app_scopes.csv"
read -p "Enter the file path to save the CSV (default: $defaultFilePath): " filePath
filePath="${filePath:-$defaultFilePath}"

# Variables
bearerToken=""
tokenExpirationEpoch="0"

# Function to get a new bearer token
getBearerToken() {
    echo "Getting a new bearer token..."
    response=$(curl -s -u "$username:$password" "$url/api/v1/auth/token" -X POST)
    bearerToken=$(echo "$response" | plutil -extract token raw -)
    tokenExpiration=$(echo "$response" | plutil -extract expires raw - | awk -F . '{print $1}')
    tokenExpirationEpoch=$(date -j -f "%Y-%m-%dT%T" "$tokenExpiration" +"%s")
    echo "Bearer token acquired. Token valid until epoch time: $tokenExpirationEpoch"
}

# Function to check if the token is still valid
checkTokenExpiration() {
    echo "Checking token expiration..."
    nowEpochUTC=$(date -j -f "%Y-%m-%dT%T" "$(date -u +"%Y-%m-%dT%T")" +"%s")
    if [[ tokenExpirationEpoch -gt nowEpochUTC ]]; then
        echo "Token is still valid."
    else
        echo "Token expired. Getting a new token..."
        getBearerToken
    fi
}

# Function to fetch mobile device apps and save to CSV
fetchAppScopes() {
    echo "Fetching the list of mobile device applications..."
    checkTokenExpiration

    # Fetch app list as XML
    rawAppList=$(curl -s -H "Authorization: Bearer ${bearerToken}" "$url/JSSResource/mobiledeviceapplications" -X GET)

    # Validate if the response contains valid XML
    echo "Validating response..."
    if ! echo "$rawAppList" | xmllint --noout - 2>/dev/null; then
        echo "Error: API did not return valid XML. Raw response saved to raw_response.xml"
        echo "$rawAppList" > raw_response.xml
        return
    fi

    echo "Response validated. Processing app details..."
    echo "App Name,Scope,Exclusions" > "$filePath"

    # Parse XML and extract app details
    appIDs=$(echo "$rawAppList" | xmllint --xpath "//mobile_device_application/id/text()" - 2>/dev/null)

    totalApps=$(echo "$appIDs" | wc -w)
    currentApp=0

    for appID in $appIDs; do
        currentApp=$((currentApp + 1))
        echo "Processing app $currentApp of $totalApps (ID: $appID)..."

        appDetails=$(curl -s -H "Authorization: Bearer ${bearerToken}" "$url/JSSResource/mobiledeviceapplications/id/$appID" -X GET)

        appName=$(echo "$appDetails" | xmllint --xpath "string(//name)" - 2>/dev/null)
        allMobileDevices=$(echo "$appDetails" | xmllint --xpath "string(//scope/all_mobile_devices)" - 2>/dev/null)

        # Fetch scope details
        mobileDevices=$(echo "$appDetails" | xmllint --xpath "//scope/mobile_devices/mobile_device/name" - 2>/dev/null | sed 's/<name>//g' | sed 's/<\/name>//g' | tr '\n' ', ')
        buildings=$(echo "$appDetails" | xmllint --xpath "//scope/buildings/building/name" - 2>/dev/null | sed 's/<name>//g' | sed 's/<\/name>//g' | tr '\n' ', ')
        departments=$(echo "$appDetails" | xmllint --xpath "//scope/departments/department/name" - 2>/dev/null | sed 's/<name>//g' | sed 's/<\/name>//g' | tr '\n' ', ')
        mobileDeviceGroups=$(echo "$appDetails" | xmllint --xpath "//scope/mobile_device_groups/mobile_device_group/name" - 2>/dev/null | sed 's/<name>//g' | sed 's/<\/name>//g' | tr '\n' ', ')

        # Fetch exclusion details
        excludedDevices=$(echo "$appDetails" | xmllint --xpath "//scope/exclusions/mobile_devices/mobile_device/name" - 2>/dev/null | sed 's/<name>//g' | sed 's/<\/name>//g' | tr '\n' ', ')
        excludedGroups=$(echo "$appDetails" | xmllint --xpath "//scope/exclusions/mobile_device_groups/mobile_device_group/name" - 2>/dev/null | sed 's/<name>//g' | sed 's/<\/name>//g' | tr '\n' ', ')

        # Build scope string
        scope=""
        if [[ "$allMobileDevices" == "true" ]]; then
            scope="All Mobile Devices"
        else
            [[ -n "$mobileDevices" ]] && scope+="Mobile Devices: $mobileDevices\n"
            [[ -n "$buildings" ]] && scope+="Buildings: $buildings\n"
            [[ -n "$departments" ]] && scope+="Departments: $departments\n"
            [[ -n "$mobileDeviceGroups" ]] && scope+="Mobile Device Groups: $mobileDeviceGroups\n"

            # If no scope values are defined
            if [[ -z "$scope" ]]; then
                scope="No scope defined"
            fi
        fi

        # Remove trailing newlines
        scope=$(echo -e "$scope" | sed '/^[[:space:]]*$/d')

        # Build exclusions string
        exclusions=""
        [[ -n "$excludedDevices" ]] && exclusions+="Excluded Devices: $excludedDevices\n"
        [[ -n "$excludedGroups" ]] && exclusions+="Excluded Groups: $excludedGroups\n"

        # Remove trailing newlines
        exclusions=$(echo -e "$exclusions" | sed '/^[[:space:]]*$/d')

        # Handle empty app name
        appName=${appName:-"N/A"}

        # Output to CSV
        echo "\"$appName\",\"$(echo -e "$scope")\",\"$(echo -e "$exclusions")\"" >> "$filePath"
        echo "App $currentApp processed: $appName"
    done

    echo "Export completed: $filePath"
}

# Main execution
echo "Starting script..."
getBearerToken
fetchAppScopes
echo "Script execution completed."
