#!/bin/bash

_get_version(){
  if [ $type == 'helm' ]; then
    local file_name=$(find $GITHUB_WORKSPACE -iname "Chart.yaml")
    echo ${version=$(yq '.version' < $file_name)}
    echo "File: $file_name"
    echo "Version: $version"
  elif [ $type == 'nodejs' ]; then
    local file_name=$(find $GITHUB_WORKSPACE -iname "package.json")
    echo ${version=$(jq '.version' ./package.json | xargs echo)}
    echo "File: $file_name"
    echo "Version: $version"
  else
    echo "Current version not found"
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

_create_tag() {
  response=$(curl -X POST \
    -H "Authorization: token $github_token" \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/repos/$repo_owner/$repo_name/git/refs \
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
if [ -z "$repo_owner" ] || [ -z "$repo_name" ] || [ -z "$github_token" ] || [ -z "$type" ] || [ -z "$semver" ]; then
  echo "One or more parameters are missing. Make sure that all parameters are passed: repo_owner, repo_name, github_token, type, semver"
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

_create_tag