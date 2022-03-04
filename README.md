<a href="https://docs.aws.amazon.com/ivs/"><img align="right" width="128px" src="./ivs-logo.svg"></a>

# Amazon IVS Broadcast iOS SDK Sample Apps

This repository contains sample apps which use the Amazon IVS Broadcast iOS SDK.

## Samples

+ **BasicBroadcast**: This is the most basic example of how to get started with the SDK.
+ **ScreenCapture**: This is a broadcast upload extension that shows how to integrate with ReplayKit.

## More Documentation

+ [Release Notes](https://docs.aws.amazon.com/ivs/latest/userguide/release-notes.html)
+ [iOS SDK Guide](https://docs.aws.amazon.com/ivs/latest/userguide/broadcast-ios.html)

## Setup

1. Clone the repository to your local machine.
1. Ensure you are using a supported version of Ruby, as [the version included with macOS is deprecated](https://developer.apple.com/documentation/macos-release-notes/macos-catalina-10_15-release-notes#Scripting-Language-Runtimes). This repository is tested with the version in [`.ruby-version`](./.ruby-version), which can be used automatically with [rbenv](https://github.com/rbenv/rbenv#installation).
1. Install the SDK dependency using CocoaPods. This can be done by running the following commands from the repository folder:
   * `bundle install`
   * `bundle exec pod install --repo-update`
   * For more information about these commands, see [Bundler](https://bundler.io/) and [CocoaPods](https://guides.cocoapods.org/using/getting-started.html).
1. Open `BasicBroadcast.xcworkspace`.
1. Since the simulator doesn't support the use of cameras or ReplayKit, there are a couple changes you need to build for device.
    1. Have an active Apple Developer account in order to build to physical devices.
    1. Modify the Bundle Identifier for both `BasicBroadcast` and `ScreenCapture` targets.
    1. Choose a Team for both targets.
    1. Create a new App Group ID based on your new Bundle Identifier for both targets, and include the targets in only that App Group.
    1. Modify `UserDefaultsDao` to use your newly created App Group ID.
1. You can now build and run the projects on a device.

## Screen Broadcasting

### Project Setup

The IVS Broadcast SDK supports easy integration with ReplayKit for screen sharing. This sample app includes a target called `ScreenCapture` that includes all the code necessary to screen share. By default, that target won't know what endpoint and stream key to use, so before you screen share you need to broadcast at least once using the Camera based app. It will then store your endpoint and stream key in the App Group you created in Setup, and that will be loaded when you screen share.

You can also hard code the endpoint and stream key in both the `ScreenCapture` and `BasicBroadcast` targets if that is easier.

### Debugging

Debugging app extensions can be awkward. In order to debug the `ScreenCapture` target, you need to:

1. Select the `ScreenCapture` scheme from the scheme dropdown.
2. Run the scheme.
    * It will ask you to choose an app to launch. You can choose anything, I usually do Calculator or Calendar because they are very lightweight.
    * Our `ScreenCapture` process won't launch yet, Xcode will wait and attach to the process later.
3. Once the app you selected has finished launching, pull up the control center and begin a screen recording session through the system UI, selecting `ScreenCapture` as your recorder.
4. After the 3, 2, 1 countdown on your device, the system will launch our process and Xcode should attach to it. At this point you can debug and use console logs.

## License
This project is licensed under the MIT-0 License. See the LICENSE file.
