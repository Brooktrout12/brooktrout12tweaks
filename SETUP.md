# Publish this repository

Target: https://github.com/Brooktrout12/Brooktrout12Tweaks

## Easiest complete-folder upload on Windows

1. Install GitHub Desktop and sign in to your GitHub account.
2. Choose File > Clone repository, select Brooktrout12/Brooktrout12Tweaks and clone it.
3. Extract the provided ZIP. Open its Brooktrout12Tweaks folder. Copy ALL contents into the cloned repository folder. Copy the contents, not the outer folder. Include .github, .gitattributes and .gitignore. Replace the placeholder README if prompted; preserve the clone's own .git directory.
4. In GitHub Desktop, use the summary `Add tweaks, source code and package repository`. Click Commit to main, then Push origin.
5. Open the repository on GitHub in a browser. Go to Settings > Pages. Under Build and deployment, set Source to GitHub Actions.
6. Open Actions > Publish tweak repository. If the initial run failed because Pages was not enabled yet, choose Run workflow, select main and run it again.
7. Wait for the build and deploy jobs to turn green. Add this URL in Sileo or Zebra:

https://brooktrout12.github.io/Brooktrout12Tweaks/

No GitHub token, paid hosting, custom domain, Python installation or iOS build toolchain is required on your Windows PC to publish these existing packages. GitHub Desktop may request the normal GitHub sign-in/authorization.

## Uploading in a browser instead

GitHub does not unpack ZIPs automatically. Upload the extracted files/folders using Add file > Upload files and commit them. The web uploader accepts up to 100 files per upload, so the full source tree will require multiple batches. GitHub Desktop is much easier for this bundle.

If your browser skips the .github folder, use Add file > Create new file, enter `.github/workflows/publish.yml` as the filename, and paste the contents of the supplied file at that same path. The workflow must be on the main branch. Then follow steps 5–7 above. Use a browser for Settings > Pages.

## Future updates

1. Replace/add the appropriate .deb in debs/rootless/ with a higher version number, preserving its Package ID for upgrades.
2. Update the matching sources/ folder with the source used to build that release. Keep all license notices.
3. For a NEW package ID, add its source folder and honest test status to catalog.json. Existing IDs already have entries.
4. Commit and push to main. The workflow rebuilds the package indexes and publishes the site automatically.
5. Refresh Sources in your package manager.

The publishing workflow indexes existing packages. It does not compile the tweaks. Each project's build instructions describe its own toolchain.

The included DEBs retain their original identifiers, versions, control fields and payloads. A few identifiers use historical local/com.chatgpt prefixes; these are deliberately preserved for installed-package upgrade continuity.

## Local checks (optional, Linux)

With Python 3 and dpkg-deb installed:

    python3 scripts/build_repo.py
    python3 scripts/verify_repo.py

The generated output is _site/. It is ignored by Git; GitHub Actions generates a fresh copy on each push. To inspect locally:

    python3 -m http.server 8080 --directory _site

GitHub Pages serves only the generated package repository. Editable sources and licenses remain browsable in the GitHub repository.
