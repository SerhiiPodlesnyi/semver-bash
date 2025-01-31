#!/bin/bash

_get_version(){
  local file_name
  if [ $type == 'helm' ]; then
    file_name=$(find $GITHUB_WORKSPACE -iname "Chart.yaml")
    echo ${version=$(yq '.version' < $file_name)}
  elif [ $type == 'nodejs' ]; then
    file_name=$(find $GITHUB_WORKSPACE -iname "package.json")
    echo ${version=$(jq '.version' $file_name | xargs echo)}
  else
    echo "Unsupported project type: $type"
    exit 1
  fi
}

_increment_version() {
  local version=$current_version
  local semver=$semver
  
  local major=$(echo "$version" | cut -d. -f1)
  local minor=$(echo "$version" | cut -d. -f2)
  local patch=$(echo "$version" | cut -d. -f3)
  
  case $semver in
      "major")
          echo "$((major + 1)).0.0"
          ;;
      "minor")
          echo "${major}.$((minor + 1)).0"
          ;;
      "patch")
          echo "${major}.${minor}.$((patch + 1))"
          ;;
      *)
          echo "Error: Unknown version type. Use: major, minor, or patch" >&2
          return 1
          ;;
  esac
}

_commit_and_push() {
  local file_to_update

  if [ "$type" == "helm" ]; then
    file_to_update=$(find "$GITHUB_WORKSPACE" -iname "Chart.yaml")
    yq -i ".version = \"$tag\"" "$file_to_update"
  elif [ "$type" == "nodejs" ]; then
    file_to_update=$(find "$GITHUB_WORKSPACE" -iname "package.json")
    jq ".version = \"$tag\"" "$file_to_update" > temp.json && mv temp.json "$file_to_update"
  else
    echo "Unsupported project type: $type"
    exit 1
  fi

  file_to_update=$(realpath --relative-to="$GITHUB_WORKSPACE" "$file_to_update")
  echo "Updated version in $file_to_update to $tag"

  # Отримуємо SHA файлу
  file_sha=$(curl -s -H "Authorization: token $github_token" \
                     -H "Accept: application/vnd.github.v3+json" \
                     "https://api.github.com/repos/$GITHUB_REPOSITORY/contents/$file_to_update" | jq -r '.sha // empty')

  if [ -z "$file_sha" ] || [ "$file_sha" == "null" ]; then
    file_sha=null
  else
    file_sha="\"$file_sha\""
  fi

  # Конвертація файлу у base64 без переносу рядків
  file_content=$(base64 "$file_to_update" | tr -d '\n')

  commit_message="Bump version to $tag"
  response=$(curl -X PUT \
    -H "Authorization: token $github_token" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/contents/$file_to_update" \
    -d "{
      \"message\": \"$commit_message\",
      \"content\": \"$file_content\",
      \"sha\": $file_sha
    }")

  if echo "$response" | grep -q '"commit"'; then
    echo "Successfully committed version bump"
  else
    echo "Failed to commit changes: $response"
    exit 1
  fi
}

_create_tag() {
  response=$(curl -X POST \
    -H "Authorization: token $github_token" \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/repos/$GITHUB_REPOSITORY/git/refs \
    -d "{\"ref\": \"refs/tags/$tag\", \"sha\": \"$(git rev-parse HEAD)\"}")

  # Check the status of the response
  if echo "$response" | grep -q '"ref":'; then
    echo "Tag successfully created: $tag"
  else
    echo "An error occurred while creating a tag: $response"
    exit 1
  fi
}


# Checking the availability of parameters
if [ -z "$github_token" ] || [ -z "$type" ] || [ -z "$semver" ]; then
  echo "One or more parameters are missing. Make sure that all parameters are passed: github_token, type, semver"
  exit 1
fi

current_version=$(_get_version)
echo "Current version: $current_version"

if ! [[ $current_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Invalid version format. Please use the format: X.Y.Z" >&2
    exit 1
fi

tag=$(_increment_version)
echo "New version: $tag"

_commit_and_push
_create_tag