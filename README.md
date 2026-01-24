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
This project is designed to work with:
- [Cobalt API](https://github.com/imputnet/cobalt)
- [Nickel-Auth](https://github.com/tfourj/Nickel-Auth) *(Works as authentication bridge for public instances)*
- [SwiftFFmpeg-iOS](https://github.com/tfourj/SwiftFFmpeg-iOS)

## Features

Visit [getnickel.site](https://getnickel.app) for the latest features and updates.

## Requirements

- iOS 17.0 or later
- iPhone or iPad
- Xcode 15.3+ (for building from source)
- Custom Cobalt API server (required for functionality)

## Installation

- Download from [TestFlight](https://getnickel.app/testflight)
- Sideload the [IPA](https://github.com/tfourj/Nickel/actions) using tools like AltStore or ESign

## Configuration

1. Open app settings
2. Enter your custom API URL and authentication details or get them from [public list](https://getnickel.app/instances)
3. Configure optional settings like auto-save and notifications

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

## Credits & Acknowledgments

Nickel uses the following libraries:

- **[FFmpeg](https://ffmpeg.org/)** - A complete, cross-platform solution to record, convert and stream audio and video. FFmpeg is licensed under [LGPL/GPL](https://ffmpeg.org/legal.html).
- **[LAME](https://lame.sourceforge.io/)** - An MP3 encoder library used for audio encoding. LAME is licensed under [LGPL](https://lame.sourceforge.io/about.php).

These libraries are integrated via [SwiftFFmpeg-iOS](https://github.com/tfourj/SwiftFFmpeg-iOS), which provides Swift bindings for FFmpeg on iOS.

## License

This project is licensed under the GPLv3 - see the [License](LICENSE) file for details.
