# check if prerequisites are installed
if ! command -v jq > /dev/null; then
  echo "You do not have jq installed."
  exit 1
fi

if ! command -v gh > /dev/null; then
  echo "You do not have Github CLI installed."
  exit 1
fi

if ! command -v wf > /dev/null; then
  echo "You do not have Wayfinder CLI installed."
  exit 1
fi

# check if user is logged in
if ! gh auth status > /dev/null; then
  echo "You are not logged in to Github CLI. Please run 'gh auth login' and try again."
  exit 1
fi

if [ "$(wf whoami | wc -l)" -eq 0 ]; then
  echo "You are not logged in to Wayfinder CLI. Please run 'wf login' and try again."
  exit 1
fi

# get secrets from user input
read -rp "Do you already have a workspace (yes/no)?: " has_workspace
if [ "$has_workspace" = "no" ]; then
  read -rp "Enter Wayfinder workspace name (lowercase 2-5 unique alphanumeric): " workspace_name
  read -rp "Enter Wayfinder workspace summary (human readable description (no spaces)): " workspace_summary
  echo "Creating workspace $workspace_name..."
  wf create workspace "$workspace_name" --summary="$workspace_summary"
  echo "Workspace $workspace_name created."
  echo "You now have to define your application environment and container components on the Wayfinder UI. Once you are done with that, run this script again to set up the GitHub repository."
  exit 0
fi

read -rp "Have you defined your application environment and container components (yes/no)?: " is_application_ready
if [ "$is_application_ready" = "no" ]; then
  echo "Your GitHub repository cannot be set up without the application environment and container components definitions."
  echo "Please define your application environment and container components on the Wayfinder UI and run this script again."
  exit 0
fi

echo "You are now ready to set up your GitHub repository!"
read -rp "Enter Wayfinder workspace name: " workspace_name
read -rp "Enter Wayfinder application name: " application_name
read -rp "Enter application environment name: " environment_name
read -rp "Enter container component name: " component_name
read -rp "Enter GitHub personal access token (classic): " github_token
read -rp "Enter GitHub reposity name: " repository_name
full_repository_name="Digital-Garage-ICL/${repository_name}"

# set the token as a Github secret
version=$(wf serverinfo -o json | jq -r .version.release)
server=$(wf profiles show -o json | jq -r .endpoint)
token=$(wf create wat "$repository_name" -w "$workspace_name" --reset-token --show-token)
gh variable set WAYFINDER_VERSION --repo "$full_repository_name" --body "$version"
gh variable set WAYFINDER_SERVER --repo "$full_repository_name" --body "$server"
gh variable set WAYFINDER_WORKSPACE --repo "$full_repository_name" --body "$workspace_name"
gh variable set WAYFINDER_APPLICATION --repo "$full_repository_name" --body "$application_name"
gh variable set WAYFINDER_ENVIRONMENT --repo "$full_repository_name" --body "$environment_name"
gh variable set WAYFINDER_COMPONENT --repo "$full_repository_name" --body "$component_name"
gh secret set WAYFINDER_TOKEN --repo "$full_repository_name" --body "$token"

# set the default workspace
wf use workspace "$workspace_name"

# allow the workspace Access Token (WAT) to manage apps, DNS, etc
wf assign wayfinderrole --workspace "$workspace_name" --workspace-access-token "$repository_name" --role workspace.appmanager
wf assign wayfinderrole --workspace "$workspace_name" --workspace-access-token "$repository_name" --role workspace.dnsmanager
wf assign wayfinderrole --workspace "$workspace_name" --workspace-access-token "$repository_name" --role workspace.accessmanager
wf assign wayfinderrole --workspace "$workspace_name" --workspace-access-token "$repository_name" --role workspace.appdeployer

wf assign accessrole --workspace "$workspace_name" --workspace-access-token "$repository_name" --role cluster.deployment --cluster aks-stdnt1
wf assign accessrole --workspace "$workspace_name" --workspace-access-token "$repository_name" --role namespace.deployment --cluster aks-stdnt1 --namespace "$workspace_name"-"$application_name"-"$environment_name"

# get access to our kubernetes namespace so that we can create a secret allowing kubernetes' kubelet to pull our container image
wf access cluster to1.aks-stdnt1 --role namespace.admin --namespace "$workspace_name"-"$application_name"-"$environment_name"

# create a k8s secret so that kubelet can pull our container image
# but delete the secret first in case it already exists
export GITHUB_TOKEN=$github_token
username=$(gh api user | jq -r '.login')
kubectl delete secret ghcr-login-secret --namespace "$workspace_name"-"$application_name"-"$environment_name" > /dev/null 2>&1 || true
kubectl create secret docker-registry ghcr-login-secret --namespace "$workspace_name"-"$application_name"-"$environment_name" --docker-username="$username" --docker-password="$github_token" --docker-server=ghcr.io
