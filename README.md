<div align="center">

<img src="Nickel/Assets.xcassets/Nickel.imageset/nickel_dark-removebg-preview.png" alt="Nickel Logo" width="200">

# Nickel
A native third-party iOS client app for [Cobalt.tools](https://cobalt.tools) that allows downloading media from various social platforms via self-hosted Cobalt API servers.\
Project was inspired from cranci1's [Osmium](https://github.com/cranci1/Osmium)

</div>

## Disclaimer
```
The app does not interface directly with social media platforms - it relies on your own Cobalt API server instance to handle the media downloads.
```

## Features

- Share links directly from any app using the iOS share sheet
- Automatic saving of downloaded files to Photos app
- Background download support with completion notifications 
- Customizable API settings and authentication
- Support for video, audio and image downloads

## Requirements

- iOS 17.0 or later
- iPhone or iPad
- Xcode 15.3+ (for building from source)
- Custom Cobalt API server (required for functionality)

## Installation

### Option 1: Build from Source

1. Clone this repository
2. Open `Nickel.xcodeproj` in Xcode
3. Configure your development team and signing certificates
4. Build and run on your device

### Option 2: Sideload Pre-built IPA

1. Download the latest IPA file from:
   - [GitHub Actions Artifacts](../../actions) (requires GitHub account)
   - [Releases](../../releases) page
2. Install using your preferred sideloading method:
   - AltStore
   - ESign 
   - Or other sideloading tools

## Configuration

1. Open app settings
2. Enter your custom API URL and authentication details
3. Configure optional settings like auto-save and notifications

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

## License

This project is licensed under the GPLv3 - see the [License](LICENSE) file for details.