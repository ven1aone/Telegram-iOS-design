# Telegram iOS Source Code Compilation Guide

We welcome all developers to use our API and source code to create applications on our platform.
There are several things we require from **all developers** for the moment.

# Creating your Telegram Application

1. [**Obtain your own api_id**](https://core.telegram.org/api/obtaining_api_id) for your application.
2. Please **do not** use the name Telegram for your app — or make sure your users understand that it is unofficial.
3. Kindly **do not** use our standard logo (white paper plane in a blue circle) as your app's logo.
3. Please study our [**security guidelines**](https://core.telegram.org/mtproto/security_guidelines) and take good care of your users' data and privacy.
4. Please remember to publish **your** code too in order to comply with the licences.

# Quick Compilation Guide

## Get the Code

```
git clone --depth 1 https://github.com/ven1aone/Telegram-iOS-design.git
cd Telegram-iOS-design
git submodule init
git config submodule.submodules/rlottie/rlottie.url https://github.com/TelegramMessenger/rlottie.git
git config submodule.submodules/TgVoipWebrtc/tgcalls.url https://github.com/TelegramMessenger/tgcalls.git
git submodule update --init --recursive --depth 1 --jobs 8
```

The two local URL overrides resolve upstream submodules whose relative URLs otherwise
point to sibling repositories under the fork owner's account. Their pinned commits
remain those recorded by this repository.

## Setup Xcode

Install Xcode (directly from https://developer.apple.com/download/applications or using the App Store).

## Adjust Configuration

1. Generate a random identifier:
```
openssl rand -hex 8
```
2. Create a new Xcode project. Use `Telegram` as the Product Name. Use `org.{identifier from step 1}` as the Organization Identifier.
3. Open `Keychain Access` and navigate to `Certificates`. Locate `Apple Development: your@email.address (XXXXXXXXXX)` and double tap the certificate. Under `Details`, locate `Organizational Unit`. This is the Team ID.
4. Edit `build-system/template_minimal_development_configuration.json`. Use data from the previous steps.

## Generate an Xcode project

```
python3 build-system/Make/Make.py \
    --cacheDir="$HOME/telegram-bazel-cache" \
    generateProject \
    --configurationPath=build-system/template_minimal_development_configuration.json \
    --xcodeManagedCodesigning
```

# Advanced Compilation Guide

## Xcode

1. Copy and edit `build-system/appstore-configuration.json`.
2. Copy `build-system/fake-codesigning`. Create and download provisioning profiles, using the `profiles` folder as a reference for the entitlements.
3. Generate an Xcode project:
```
python3 build-system/Make/Make.py \
    --cacheDir="$HOME/telegram-bazel-cache" \
    generateProject \
    --configurationPath=configuration_from_step_1.json \
    --codesigningInformationPath=directory_from_step_2
```

## IPA

1. Repeat the steps from the previous section. Use distribution provisioning profiles.
2. Run:
```
python3 build-system/Make/Make.py \
    --cacheDir="$HOME/telegram-bazel-cache" \
    build \
    --configurationPath=...see previous section... \
    --codesigningInformationPath=...see previous section... \
    --buildNumber=100001 \
    --configuration=release_arm64
```

# FAQ

## Xcode is stuck at "build-request.json not updated yet"

Occasionally, you might observe the following message in your build log:
```
"/Users/xxx/Library/Developer/Xcode/DerivedData/Telegram-xxx/Build/Intermediates.noindex/XCBuildData/xxx.xcbuilddata/build-request.json" not updated yet, waiting...
```

Should this occur, simply cancel the ongoing build and initiate a new one.

## Telegram_xcodeproj: no such package 

Following a system restart, the auto-generated Xcode project might encounter a build failure accompanied by this error:
```
ERROR: Skipping '@rules_xcodeproj_generated//generator/Telegram/Telegram_xcodeproj:Telegram_xcodeproj': no such package '@rules_xcodeproj_generated//generator/Telegram/Telegram_xcodeproj': BUILD file not found in directory 'generator/Telegram/Telegram_xcodeproj' of external repository @rules_xcodeproj_generated. Add a BUILD file to a directory to mark it as a package.
```

If you encounter this issue, re-run the project generation steps in the README.


# Tips

## Local simulator build on Apple Silicon

Verified configuration: Xcode 27.1 beta (27A9269), the iOS 27.1 SDK and runtime,
and an existing iPhone Duo simulator. The full build, installation, and welcome
screen have been checked with this configuration.

The compiler and Bazel versions are pinned in `versions.json`. `Make.py` downloads
the matching Bazel binary and checks its SHA-256 automatically. When using a newer
installed Xcode, pass `--overrideXcodeVersion` as shown below.

For Xcode 27.1 beta unpacked in Downloads, select it for this shell before running
build or simulator commands:

```sh
export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
export BAZEL_ALLOW_NON_APPLICATIONS_XCODE=1
xcodebuild -version
```

`BAZEL_ALLOW_NON_APPLICATIONS_XCODE=1` lets the Apple C/C++ toolchain register
system include paths from Xcode installations outside `/Applications`. It is
required here because the beta is in Downloads; otherwise Bazel rejects SDK
headers as absolute, non-builtin includes.

For the initial simulator build, use the repository's stock configuration and
bundled fake provisioning data. No certificate import, Apple Developer team, or
access to the private signing repository is needed for this simulator workflow.
For simulator development with your own API credentials, copy the stock configuration
to the ignored `build-input/development-configuration.json`, update `api_id` and
`api_hash`, and pass that local file's path instead. This simulator recipe uses the
stock bundle and team IDs to match the bundled fake provisioning data. For a custom
bundle ID or device signing, follow **Adjust Configuration** and use matching
provisioning data or Xcode-managed signing.

Run from the repository root:

```sh
mkdir -p build/local-simulator
python3 -u build-system/Make/Make.py \
    --overrideXcodeVersion \
    --cacheDir="$HOME/telegram-bazel-cache" \
    build \
    --configurationPath=build-system/appstore-configuration.json \
    --codesigningInformationPath=build-system/fake-codesigning \
    --buildNumber=100001 \
    --configuration=debug_sim_arm64 \
    > build/local-simulator/build-27.1-beta.log 2>&1
```

Choose an available **iPhone Duo running iOS 27.1** with
`xcrun simctl list devices available`, then set `SIMULATOR_ID` to its UDID. Boot
it if it is shut down. In Xcode 27, simulated devices are displayed in
[Device Hub](https://developer.apple.com/documentation/xcode/device-hub):

```sh
SIMULATOR_ID="<iPhone Duo simulator UDID>"
xcrun simctl boot "$SIMULATOR_ID"
open "$DEVELOPER_DIR/../Applications/DeviceHub.app"
xcrun simctl bootstatus "$SIMULATOR_ID" -b
```

Install the application extracted from the **current `.ipa`**. The intermediate
`Telegram_archive-root` directory may contain binaries from an earlier build.
Increase `--buildNumber` on subsequent builds so the simulator installs the new
bundle while retaining its account data.

```sh
SIMULATOR_STAGE=$(mktemp -d)
unzip -q bazel-bin/Telegram/Telegram.ipa -d "$SIMULATOR_STAGE"
xcrun simctl install "$SIMULATOR_ID" "$SIMULATOR_STAGE/Payload/Telegram.app"
xcrun simctl launch "$SIMULATOR_ID" ph.telegra.Telegraph
xcrun simctl io "$SIMULATOR_ID" screenshot --display=1 build/local-simulator/launch.png
rm -r "$SIMULATOR_STAGE"
```

The stock configuration's bundle ID is `ph.telegra.Telegraph`. If you use your own
configuration, use its `bundle_id` when launching. To record a feature demo, run
`xcrun simctl io "$SIMULATOR_ID" recordVideo --display=1 build/local-simulator/demo.mov`,
perform the scenario in Device Hub, then stop recording with Control-C. The current
setup checklist and diagnostic output are kept in ignored `build/local-simulator/`.

## Codesigning is not required for simulator-only builds

Add `--disableProvisioningProfiles`:
```
python3 build-system/Make/Make.py \
    --cacheDir="$HOME/telegram-bazel-cache" \
    generateProject \
    --configurationPath=path-to-configuration.json \
    --codesigningInformationPath=path-to-provisioning-data \
    --disableProvisioningProfiles
```

## Versions

Each release is built using a specific Xcode version (see `versions.json`). The helper script checks the versions of the installed software and reports an error if they don't match the ones specified in `versions.json`. It is possible to bypass these checks:

```
python3 build-system/Make/Make.py --overrideXcodeVersion build ... # Don't check the version of Xcode
```
