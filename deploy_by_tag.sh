#!/bin/env sh

_get_version(){
  if [ $type == 'helm' ]; then
    local file_name=$(find . -iname "Chart.yaml")
    echo ${version=$(yq '.version' < $file_name)}
  elif [ $type == 'nodejs' ]; then
    local file_name=$(find . -iname "package.json")
    echo ${version=$(jq '.version' ./package.json | xargs echo)}
  else
    echo "Current version not found"
  fi
}

_increment_version() {
  local version=$current_version
  local type=$semver
  
  # Розбиваємо версію на компоненти
  IFS='.' read -r major minor patch <<< "$version"
  
  case $type in
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
          exit 1
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

wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq &&\
    chmod +x /usr/bin/yq

wget -O jq https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 &&\
    chmod +x ./jq

current_version=$(_get_version)
echo $current_version

if ! [[ $current_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Invalid version format. Please use the format: X.Y.Z" >&2
    exit 1
fi

tag=$(_increment_version)

_create_tag