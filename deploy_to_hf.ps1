# deploy_to_hf.ps1
# Deploys the backend (recorder branch) to Hugging Face Spaces.
# Strips out the chess_game folder which contains binary files rejected by HF.
# Your local recorder branch and GitHub remain completely unchanged.

Write-Host "Starting Hugging Face deployment..." -ForegroundColor Cyan

# Make sure we're on recorder
$currentBranch = git rev-parse --abbrev-ref HEAD
if ($currentBranch -ne "recorder") {
    Write-Host "Not on recorder branch. Switching..." -ForegroundColor Yellow
    git checkout recorder
}

# Create a clean temp branch from current state
Write-Host "Creating clean deployment branch..." -ForegroundColor Blue
git checkout -b _hf-temp

# Remove chess_game folder from the branch history
Write-Host "Removing chess_game assets from deployment history..." -ForegroundColor Blue
git filter-repo --path chess_game/ --invert-paths --force

# Push to Hugging Face
Write-Host "Pushing to Hugging Face..." -ForegroundColor Blue
git push hf _hf-temp:main --force

# Restore recorder branch and delete temp
Write-Host "Restoring recorder branch..." -ForegroundColor Blue
git checkout recorder
git branch -D _hf-temp

Write-Host "Deployment complete! Your recorder branch is untouched." -ForegroundColor Green
