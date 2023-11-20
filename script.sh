rm -r src/App
rm src/keycloak-theme/login/valuesTransferredOverUrl.ts
mv src/keycloak-theme/* src/
rm -r src/keycloak-theme

cat << EOF > src/index.tsx
import { createRoot } from "react-dom/client";
import { StrictMode, lazy, Suspense } from "react";
import { kcContext as kcLoginThemeContext } from "./login/kcContext";
import { kcContext as kcAccountThemeContext } from "./account/kcContext";

const KcLoginThemeApp = lazy(() => import("./login/KcApp"));
const KcAccountThemeApp = lazy(() => import("./account/KcApp"));

createRoot(document.getElementById("root")!).render(
    <StrictMode>
        <Suspense>
            {(()=>{

                if( kcLoginThemeContext !== undefined ){
                    return <KcLoginThemeApp kcContext={kcLoginThemeContext} />;
                }

                if( kcAccountThemeContext !== undefined ){
                    return <KcAccountThemeApp kcContext={kcAccountThemeContext} />;
                }

                throw new Error(
                  "This app is a Keycloak theme" +
                  "It isn't meant to be deployed outside of Keycloak"
                );

            })()}
        </Suspense>
    </StrictMode>
);

EOF

rm .dockerignore Dockerfile nginx.conf

cat << EOF > .github/workflows/ci.yaml
name: ci
on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

jobs:

  build:
    runs-on: ubuntu-latest
    if: github.event.head_commit.author.name != 'actions'
    steps:
    - uses: actions/checkout@v2
    - uses: actions/setup-node@v2.1.3
      with:
        node-version: '16'
    - uses: bahmutov/npm-install@v1
    - run: yarn build
    - run: npx keycloakify
    - uses: actions/upload-artifact@v2
      with:
        name: standalone_keycloak_theme
        path: build_keycloak/target/*keycloak-theme*.jar
    - uses: actions/upload-artifact@v2
      with:
        name: build
        path: build

  check_if_version_upgraded:
    name: Check if version upgrade
    runs-on: ubuntu-latest
    needs: build
    outputs:
      from_version: \${{ steps.step1.outputs.from_version }}
      to_version: \${{ steps.step1.outputs.to_version }}
      is_upgraded_version: \${{ steps.step1.outputs.is_upgraded_version }}
    steps:
    - uses: garronej/ts-ci@v2.1.0
      id: step1
      with: 
        action_name: is_package_json_version_upgraded

  create_github_release:
    runs-on: ubuntu-latest
    needs: 
      - check_if_version_upgraded
    # We create a release only if the version have been upgraded and we are on a default branch
    # PR on the default branch can release beta but not real release
    if: |
      needs.check_if_version_upgraded.outputs.is_upgraded_version == 'true' &&
      (
        github.event_name == 'push' ||
        needs.check_if_version_upgraded.outputs.is_release_beta == 'true'
      )
    steps:
    - run: mkdir jars
    - uses: actions/download-artifact@v2
      with:
        name: standalone_keycloak_theme
    - run: mv *keycloak-theme*.jar jars/standalone-keycloak-theme.jar
    - uses: softprops/action-gh-release@v1
      with:
        name: Release v\${{ needs.check_if_version_upgraded.outputs.to_version }}
        tag_name: v\${{ needs.check_if_version_upgraded.outputs.to_version }}
        target_commitish: \${{ github.head_ref || github.ref }}
        generate_release_notes: true
        files: |
          jars/standalone-keycloak-theme.jar
        draft: false
        prerelease: \${{ needs.check_if_version_upgraded.outputs.is_release_beta == 'true' }}
      env:
        GITHUB_TOKEN: \${{ secrets.GITHUB_TOKEN }}
EOF
