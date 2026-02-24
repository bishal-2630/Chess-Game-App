# F-Droid Submission Guide for Chess App

Now that the code is prepared on the `fdroid` branch, here are the steps to actually submit your app to the F-Droid repository.

## 1. Prerequisites
- Your code must be hosted on a public repository (GitHub/GitLab).
- All proprietary libraries (Google Services, etc.) must be removed (Completed on the `fdroid` branch).
- The app must build using only open-source tools.

## 2. Metadata Preparation
F-Droid uses a metadata file to know how to build your app. You can either:
- **Submit a Merge Request to F-Droid Data**: This is the traditional way.
- **Use an F-Droid Repository for Updates**: (Optional) For faster updates, you can host your own repo.

### Metadata File Template (`com.bishalkhadka.chess.yml`)
You will need to provide this information during submission:

```yaml
Categories:
  - Games
License: MIT
AuthorName: Bishal Khadka
SourceCode: https://github.com/bishal-2630/Chess-Game-App/tree/fdroid
IssueTracker: https://github.com/bishal-2630/Chess-Game-App/issues

RepoType: git
Repo: https://github.com/bishal-2630/Chess-Game-App

Builds:
  - versionName: 1.0.0
    versionCode: 1
    commit: 87d1ce24b872c038e932c8e88324f3abd7c80e07
    subdir: chess_game
    gradle:
      - yes
    flutter: yes

AutoName: Chess Game
Description: |
    A beautiful chess game with Django authentication (Email/Password and Guest login supported).
    This version is completely free of proprietary SDKs.
```

## 3. Submission Steps

1.  **Fork the [fdroiddata](https://gitlab.com/fdroid/fdroiddata) repository** on GitLab.
2.  **Add your metadata file**: Create a new file in `metadata/com.bishalkhadka.chess.yml` using the template above (make sure to replace the commit hash).
3.  **Test the build**: Use the `fdroid build` command (requires F-Droid server tools) to ensure it builds correctly.
4.  **Open a Merge Request**: Submit your changes back to the main `fdroiddata` repo.

## 4. Maintenance
F-Droid will periodically check your repository for new tags/releases. Make sure to tag your releases on the `fdroid` branch for F-Droid to pick them up automatically.
