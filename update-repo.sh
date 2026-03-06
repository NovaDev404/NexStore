#!/bin/sh
# this shouldn't be ran when testing, only when building via workflow

handle_error() {
  echo "Error: $1" >&2
  exit 1
}

REPO="NovaDev404/NexStore"
API_URL="https://api.github.com/repos/$REPO/releases/latest"

echo "Fetching latest release data from GitHub..."

attempt=1
max_attempts=10
release_info=""

while [ $attempt -le $max_attempts ]; do
  echo "Attempt $attempt to fetch release info..."

  release_info=$(curl -s \
    -H "Accept: application/vnd.github+json" \
    -H "User-Agent: NexStore-Repo-Updater" \
    "$API_URL")

  if [ -z "$release_info" ]; then
    echo "Empty response from API"
  else
    api_message=$(echo "$release_info" | jq -r '.message // empty')

    if [ -n "$api_message" ]; then
      echo "GitHub API message: $api_message"
    else
      assets_count=$(echo "$release_info" | jq '(.assets // []) | length')

      if [ "$assets_count" -gt 0 ]; then
        echo "Assets detected."
        break
      fi
    fi
  fi

  if [ $attempt -lt $max_attempts ]; then
    echo "No assets found yet, retrying in 5 seconds..."
    sleep 5
  fi

  attempt=$((attempt + 1))
done

clean_release_info=$(echo "$release_info" | tr -d '\000-\037')

updated_at=$(echo "$clean_release_info" | jq -r '.published_at // .created_at // empty')
version=$(echo "$clean_release_info" | jq -r '.tag_name | sub("^v";"") // empty')

echo "Release version: $version"
echo "Updated at: $updated_at"

echo "Assets found:"
echo "$clean_release_info" | jq -r '(.assets // [])[]?.name'

ipa_files=$(echo "$clean_release_info" | jq '
[
  (.assets // [])[]
  | select((.name | endswith(".ipa")) or (.name | endswith(".tipa")))
  | {
      name: .name,
      size: (.size | tonumber),
      download_url: .browser_download_url
    }
]')

if [ "$(echo "$ipa_files" | jq 'length')" -gt 0 ]; then

  echo "Found IPA/TIPA files in release:"
  echo "$ipa_files" | jq -r '.[] | "• \(.name) (\(.size) bytes)"'

  JSON_FILE="app-repo.json"

  if [ ! -f "$JSON_FILE" ]; then
    handle_error "$JSON_FILE does not exist."
  fi

  num_apps=$(jq '.apps | length' "$JSON_FILE")
  echo "Repository has $num_apps apps"

  for app_index in $(seq 0 $((num_apps - 1))); do

    app_name=$(jq -r ".apps[$app_index].name" "$JSON_FILE")
    app_id=$(jq -r ".apps[$app_index].bundleIdentifier" "$JSON_FILE")

    echo "Processing app[$app_index]: $app_name ($app_id)"

    matching_file=""

    if echo "$app_name" | grep -i "idevice" > /dev/null; then
      matching_file=$(echo "$ipa_files" | jq '
        map(select((.name | endswith(".tipa")) or (.name | test("idevice"; "i"))))
        | first')
    else
      matching_file=$(echo "$ipa_files" | jq '
        map(select((.name | endswith(".ipa")) and (.name | test("idevice"; "i") | not)))
        | first')
    fi

    if [ "$matching_file" = "null" ] || [ -z "$matching_file" ]; then
      matching_file=$(echo "$ipa_files" | jq 'first')
      echo "No specific match found for $app_name, using first available file"
    fi

    if [ "$matching_file" != "null" ] && [ -n "$matching_file" ]; then

      name=$(echo "$matching_file" | jq -r '.name')
      size=$(echo "$matching_file" | jq -r '.size')
      download_url=$(echo "$matching_file" | jq -r '.download_url')

      echo "Updating $app_name with: $name"

      tmp_file="${JSON_FILE}.tmp"

      jq \
        --arg index "$app_index" \
        --arg version "$version" \
        --arg date "$updated_at" \
        --argjson size "$size" \
        --arg url "$download_url" \
        '
        .apps[$index | tonumber].version = $version |
        .apps[$index | tonumber].versionDate = $date |
        .apps[$index | tonumber].size = $size |
        .apps[$index | tonumber].downloadURL = $url |
        .apps[$index | tonumber].versions = [{
          version: $version,
          date: $date,
          size: $size,
          downloadURL: $url
        }]
        ' "$JSON_FILE" > "$tmp_file"

      if jq '.' "$tmp_file" >/dev/null 2>&1; then
        mv "$tmp_file" "$JSON_FILE"
      else
        echo "Error: JSON became invalid, aborting update"
        rm -f "$tmp_file"
      fi

    else
      echo "No matching file found for $app_name"
    fi

  done

  echo "Repository update completed"

else
  echo "No .ipa or .tipa files found in the latest release."
fi
