# Blue Light Filter Script

This Bash script (`bluelightfilter.sh`) automatically adjusts your screen's warmth (gamma settings) to reduce blue light exposure based on the time of day, local weather conditions, and whether a fullscreen application is running. It uses `xrandr` to modify screen gamma, making it warmer at night or during cloudy weather to promote better sleep and reduce eye strain.

## Features

- **Time-Based Adjustment**: Warms the screen at night based on local sunrise and sunset times.
- **Weather-Based Adjustment**: Applies an intermediate gamma setting during cloudy weather to balance visibility and comfort.
- **Fullscreen Detection**: Reverts to neutral gamma when a fullscreen application (e.g., video player or game) is active to preserve color accuracy.
- **Caching**: Minimizes API calls by caching location coordinates, sunrise/sunset times, and weather data for 24 hours or 1 hour, respectively.
- **Logging**: Maintains a log file for debugging and monitoring.
- **Multi Screen Support**: Added thanks to @dm+ (from PCLOS forum)

## Prerequisites

- **Operating System**: Linux with X11 display server.
- **Dependencies**:
  - `curl`: For making API requests.
  - `jq`: For parsing JSON responses from APIs.
  - `xrandr`: For adjusting screen gamma settings.
- **Optional (for fullscreen detection, at least one of)**:
  - `xdotool` (preferred)
  - `wmctrl`
  - `xwininfo`
- **Internet Connection**: Required to fetch location, sunrise/sunset, and weather data.

### Install dependencies on Debian/Ubuntu:

```bash
sudo apt update
sudo apt install curl jq x11-xserver-utils xdotool wmctrl x11-utils
````

## Installation

Clone or download this repository:

```bash
git clone <repository-url>
cd <repository-directory>
```

Make the script executable:

```bash
chmod +x bluelightfilter.sh
```

## Usage

Run the script with the default location (Santiago, Chile) or specify a custom location.

### Basic Usage

```bash
./bluelightfilter.sh
```

### Specify a Custom Location

```bash
./bluelightfilter.sh -location "New York, USA"
```

### Other params:

```bash
-nofs # No fullscreen detection
-noweather # Skip weather checks
-sunrise HH:MM # Ignore API sunrise time (24H)
-sunset HH:MM # Ignhore API sunset time (24H)
-cleancache # Clean cache and force query to APIs
```

### Running in the Background

```bash
./bluelightfilter.sh -location "Your City, Country" &
```

### Stopping the Script

```bash
ps aux | grep bluelightfilter.sh
kill <process-id>
```

## How It Works

### Initialization

* Checks for required tools (`curl`, `jq`, `xrandr`) and optional fullscreen detection tools.
* Creates cache (`~/.cache/bluelightfilter`) and log directories (`~/tmp`).
* Logs activity to `~/tmp/bluelightfilter.log`.

### Location and Data Fetching

* Retrieves coordinates for the specified location using the OpenStreetMap API.
* Fetches sunrise and sunset times from the SunriseSunset API.
* Checks local weather using the OpenMeteo API (no API key required).
* Caches data to reduce API calls.

### Screen Adjustment Logic

* **Night**: Applies warm gamma `1.0:0.9:0.8` after sunset or before sunrise.
* **Day (Clear Weather)**: Applies neutral gamma `1.0:1.0:1.0` for accurate colors.
* **Day (Cloudy Weather)**: Applies intermediate gamma `1.0:0.95:0.85` for comfort.
* **Fullscreen Mode**: Reverts to neutral gamma when a fullscreen application is detected.

### Loop

* Checks for fullscreen applications every 3 seconds.
* Updates sunrise/sunset data every 10 minutes.
* Updates weather data every hour during the day.

## Configuration

The script uses the following defaults, which can be modified directly in the script:

* **Default Location**: Santiago, Chile
* **Gamma Settings**:

  * Neutral: `1.0:1.0:1.0`
  * Night: `1.0:0.9:0.8`
  * Cloudy: `1.0:0.95:0.85`
* **Cache TTL**:

  * Coordinates and sunrise/sunset: 24 hours
  * Weather: 1 hour

## Log File

The script logs its activity to `~/tmp/bluelightfilter.log`. Logs are rotated daily to prevent excessive growth. Check the log for debugging:

```bash
cat ~/tmp/bluelightfilter.log
```

## Troubleshooting

* **"Error: \<tool> is not installed"**: Install the missing tool using your package manager.
* **"Failed to fetch coordinates/sunrise/sunset/weather"**: Check your internet connection or try a different location.
* **Gamma not changing**: Ensure `xrandr` is installed and your display supports gamma adjustments.
* **Fullscreen detection not working**: Install `xdotool`, `wmctrl`, or `xwininfo`, or check if your window manager supports fullscreen detection.

## Contributing

Feel free to submit issues or pull requests to improve the script. Suggestions for additional features, such as custom gamma profiles or alternative APIs, are welcome.

## License

This project is licensed under the MIT License. See the LICENSE file for details.

## Acknowledgments

* **APIs used**: OpenStreetMap, SunriseSunset, OpenMeteo.
* **Tools**: `xrandr`, `curl`, `jq`, `xdotool`, `wmctrl`, `xwininfo`.

## Crypto Tips
https://plisio.net/donate/GevVszjz

