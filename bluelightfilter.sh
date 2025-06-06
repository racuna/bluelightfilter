#!/bin/bash

# Blue Light Filter Script (Version NNN)
# Adjusts screen warmth based on time, weather, and fullscreen applications

# Default location
DEFAULT_LOCATION="Santiago, Chile"
LOCATION="$DEFAULT_LOCATION"
CACHE_DIR="$HOME/.cache/bluelightfilter"
LOG_DIR="$HOME/tmp"
LOG_FILE="$LOG_DIR/bluelightfilter.log"
COORDINATES_CACHE="$CACHE_DIR/coordinates.cache"
SUNRISE_SUNSET_CACHE="$CACHE_DIR/sunrise_sunset.cache"
WEATHER_CACHE="$CACHE_DIR/weather.cache"
CACHE_TTL=86400 # 24 hours in seconds for coordinates
WEATHER_TTL=3600 # 1 hour in seconds for weather

# Screen warmth settings (gamma values for xrandr)
NEUTRAL_GAMMA="1.0:1.0:1.0"
NIGHT_GAMMA="1.0:0.9:0.8"      # Warm
CLOUDY_GAMMA="1.0:0.95:0.85"    # Intermediate

# Current gamma state
CURRENT_GAMMA="$NEUTRAL_GAMMA"  # Initialize with neutral gamma

# Flags for parameters
NO_FULLSCREEN=0
NO_WEATHER=0
CLEAN_CACHE=0
MANUAL_SUNRISE=""
MANUAL_SUNSET=""

# Check for required tools
check_tools() {
    local tools=("curl" "jq" "xrandr")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            echo "Error: $tool is not installed" | tee -a "$LOG_FILE"
            exit 1
        fi
    done
}

# Check for fullscreen detection tools (in order of preference)
check_fullscreen_tool() {
    if [[ $NO_FULLSCREEN -eq 1 ]]; then
        FULLSCREEN_TOOL="none"
        return
    fi
    if command -v xdotool &>/dev/null; then
        FULLSCREEN_TOOL="xdotool"
    elif command -v wmctrl &>/dev/null; then
        FULLSCREEN_TOOL="wmctrl"
    elif command -v xwininfo &>/dev/null; then
        FULLSCREEN_TOOL="xwininfo"
    else
        echo "Warning: No fullscreen detection tool available (xdotool, wmctrl, xwininfo)" | tee -a "$LOG_FILE"
        FULLSCREEN_TOOL="none"
    fi
}

# Initialize directories and log
init_logging() {
    if [[ $CLEAN_CACHE -eq 1 && -d "$CACHE_DIR" ]]; then
        rm -rf "$CACHE_DIR"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Cleared cache directory: $CACHE_DIR" >> "$LOG_FILE"
    fi
    mkdir -p "$CACHE_DIR" "$LOG_DIR"
    # Rotate log if older than 24 hours
    if [[ -f "$LOG_FILE" ]]; then
        find "$LOG_DIR" -name "bluelightfilter.log" -mtime +1 -delete
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting bluelightfilter.sh" > "$LOG_FILE"
}

# Parse command-line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -location)
                LOCATION="$2"
                shift 2
                ;;
            -nofs)
                NO_FULLSCREEN=1
                shift
                ;;
            -noweather)
                NO_WEATHER=1
                shift
                ;;
            -cleancache)
                CLEAN_CACHE=1
                shift
                ;;
            -sunrise)
                MANUAL_SUNRISE="$2"
                shift 2
                ;;
            -sunset)
                MANUAL_SUNSET="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1" | tee -a "$LOG_FILE"
                exit 1
                ;;
        esac
    done
}

# Validate time format (HH:MM)
validate_time() {
    local time="$1"
    if [[ "$time" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Get coordinates from OpenStreetMap API
get_coordinates() {
    if [[ -f "$COORDINATES_CACHE" && $(( $(date +%s) - $(stat -c %Y "$COORDINATES_CACHE") )) -lt $CACHE_TTL ]]; then
        read -r LAT LON < "$COORDINATES_CACHE"
        if [[ -n "$LAT" && -n "$LON" ]]; then
            echo "Using cached coordinates: $LAT, $LON" | tee -a "$LOG_FILE"
            return
        fi
        echo "Warning: Invalid coordinates in cache, fetching new data" | tee -a "$LOG_FILE"
    fi

    local query=$(echo "$LOCATION" | tr ' ' '+')
    local url="https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1"
    local response
    response=$(curl -4 -s - discos -m 5 -A "bluelightfilter.sh" "$url")

    if [[ $? -ne  0 ]]; then
        echo "Error: Failed to fetch coordinates for $LOCATION" | tee -a "$LOG_FILE"
        LAT="-33.4489" # Default: Santiago, Chile
        LON="-70.6693"
        return
    fi

    LAT=$(echo "$response" | jq -r '.[0].lat')
    LON=$(echo "$response" | jq -r '.[0].lon')

    if [[ -z "$LAT" || -z "$LON" ]]; then
        echo "Error: Invalid coordinates for $LOCATION, using default" | tee -a "$LOG_FILE"
        LAT="-33.4489"
        LON="-70.6693"
    else
        echo "$LAT $LON" > "$COORDINATES_CACHE"
        echo "Fetched coordinates: $LAT, $LON" | tee -a "$LOG_FILE"
    fi
}

# Get sunrise and sunset times
get_sunrise_sunset() {
    local current_date=$(date +%Y-%m-%d)
    local cache_date=""
    local cached_sunrise=""
    local cached_sunset=""

    # Validate manual sunrise and sunset times if provided
    if [[ -n "$MANUAL_SUNRISE" ]]; then
        if ! validate_time "$MANUAL_SUNRISE"; then
            echo "Error: Invalid sunrise time format: $MANUAL_SUNRISE, using default 07:00" | tee -a "$LOG_FILE"
            MANUAL_SUNRISE="07:00"
        fi
    fi
    if [[ -n "$MANUAL_SUNSET" ]]; then
        if ! validate_time "$MANUAL_SUNSET"; then
            echo "Error: Invalid sunset time format: $MANUAL_SUNSET, using default 20:00" | tee -a "$LOG_FILE"
            MANUAL_SUNSET="20:00"
        fi
    fi

    # If both manual sunrise and sunset are provided, skip API and cache
    if [[ -n "$MANUAL_SUNRISE" && -n "$MANUAL_SUNSET" ]]; then
        SUNRISE="${MANUAL_SUNRISE}:00"
        SUNSET="${MANUAL_SUNSET}:00"
        echo "Using manual sunrise/sunset: $SUNRISE, $SUNSET" | tee -a "$LOG_FILE"
        return
    fi

    # Check if cache exists and read cache date
    if [[ -f "$SUNRISE_SUNSET_CACHE" ]]; then
        read -r cache_date cached_sunrise cached_sunset < "$SUNRISE_SUNSET_CACHE"
        if [[ "$cache_date" == "$current_date" && -n "$cached_sunrise" && -n "$cached_sunset" ]]; then
            SUNRISE="$cached_sunrise"
            SUNSET="$cached_sunset"
            echo "Using cached sunrise/sunset: $SUNRISE, $SUNSET (from $cache_date)" | tee -a "$LOG_FILE"
            return
        fi
        echo "Cache outdated or invalid (date: $cache_date), fetching new sunrise/sunset" | tee -a "$LOG_FILE"
    fi

    # Use manual sunrise or sunset if only one is provided
    if [[ -n "$MANUAL_SUNRISE" ]]; then
        SUNRISE="${MANUAL_SUNRISE}:00"
    fi
    if [[ -n "$MANUAL_SUNSET" ]]; then
        SUNSET="${MANUAL_SUNSET}:00"
    fi

    # Fetch from API only if at least one time is missing
    if [[ -z "$SUNRISE" || -z "$SUNSET" ]]; then
        local url="https://api.sunrisesunset.io/json?lat=$LAT&lng=$LON&date=today"
        local response
        response=$(curl -4 -s -m 5 "$url")

        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to fetch sunrise/sunset times" | tee -a "$LOG_FILE"
            SUNRISE=${SUNRISE:-"07:00:00"}
            SUNSET=${SUNSET:-"20:00:00"}
            return
        fi

        local api_sunrise=$(echo "$response" | jq -r '.results.sunrise')
        local api_sunset=$(echo "$response" | jq -r '.results.sunset')

        # Convert AM/PM to 24-hour format
        if [[ -n "$api_sunrise" && -n "$api_sunset" ]]; then
            api_sunrise=$(date -d "$api_sunrise" +%H:%M:%S 2>/dev/null || echo "07:00:00")
            api_sunset=$(date -d "$api_sunset" +%H:%M:%S 2>/dev/null || echo "20:00:00")
        else
            echo "Error: Invalid sunrise/sunset data, using defaults" | tee -a "$LOG_FILE"
            api_sunrise="07:00:00"
            api_sunset="20:00:00"
        fi

        SUNRISE=${SUNRISE:-$api_sunrise}
        SUNSET=${SUNSET:-$api_sunset}
    fi

    # Validate times
    if ! date -d "$SUNRISE" >/dev/null 2>&1 || ! date -d "$SUNSET" >/dev/null 2>&1; then
        echo "Error: Invalid time format for sunrise/sunset, using defaults" | tee -a "$LOG_FILE"
        SUNRISE="07:00:00"
        SUNSET="20:00:00"
    else
        echo "$current_date $SUNRISE $SUNSET" > "$SUNRISE_SUNSET_CACHE"
        echo "Fetched sunrise/sunset: $SUNRISE, $SUNSET for $current_date" | tee -a "$LOG_FILE"
    fi
}

# Check if it's day or night
is_daytime() {
    local now=$(date +%s)
    local sunrise_time
    local sunset_time

    # Validate sunrise and sunset times
    sunrise_time=$(date -d "$SUNRISE" +%s 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        echo "Error: Invalid sunrise time format: $SUNRISE, using default 07:00:00" | tee -a "$LOG_FILE"
        sunrise_time=$(date -d "07:00:00" +%s)
    fi

    sunset_time=$(date -d "$SUNSET" +%s 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        echo "Error: Invalid sunset time format: $SUNSET, using default 20:00:00" | tee -a "$LOG_FILE"
        sunset_time=$(date -d "20:00:00" +%s)
    fi

    if [[ $now -ge $sunrise_time && $now -lt $sunset_time ]]; then
        return 0 # Day
    else
        return 1 # Night
    fi
}

# Get weather from OpenMeteo API (no API key required)
get_weather() {
    if [[ $NO_WEATHER -eq 1 ]]; then
        WEATHER="unknown"
        return
    fi

    if [[ -f "$WEATHER_CACHE" && $(( $(date +%s) - $(stat -c %Y "$WEATHER_CACHE") )) -lt $WEATHER_TTL ]]; then
        WEATHER=$(cat "$WEATHER_CACHE")
        if [[ -n "$WEATHER" ]]; then
            echo "Using cached weather: $WEATHER" | tee -a "$LOG_FILE"
            return
        fi
        echo "Warning: Invalid weather in cache, fetching new data" | tee -a "$LOG_FILE"
    fi

    local url="https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&current_weather=true"
    local response
    response=$(curl -4 -s -m 5 "$url")

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to fetch weather data from OpenMeteo" | tee -a "$LOG_FILE"
        WEATHER="unknown"
        return
    fi

    # Map OpenMeteo weather codes to simplified conditions
    local weather_code
    weather_code=$(echo "$response" | jq -r '.current_weather.weathercode')

    if [[ -z "$weather_code" ]]; then
        echo "Error: Invalid weather data from OpenMeteo" | tee -a "$LOG_FILE"
        WEATHER="unknown"
    else
        case "$weather_code" in
            0) WEATHER="Clear" ;; # Clear sky
            1|2|3) WEATHER="Clouds" ;; # Mainly clear, partly cloudy, overcast
            *) WEATHER="Clouds" ;; # All others (rain, snow, etc.) treated as non-clear
        esac
        echo "$WEATHER" > "$WEATHER_CACHE"
        echo "Fetched weather from OpenMeteo: $WEATHER (code: $weather_code)" | tee -a "$LOG_FILE"
    fi
}

# Check if an application is in fullscreen
is_fullscreen() {
    if [[ $NO_FULLSCREEN -eq 1 ]]; then
        return 1 # Skip fullscreen check
    fi

    case "$FULLSCREEN_TOOL" in
        xdotool)
            local active_window=$(xdotool getactivewindow)
            local window_state=$(xdotool getwindowgeometry --shell "$active_window" | grep -E 'WIDTH|HEIGHT')
            local screen_size=$(xdpyinfo | grep dimensions | awk '{print $2}')
            local screen_width=$(echo "$screen_size" | cut -d'x' -f1)
            local screen_height=$(echo "$screen_size" | cut -d'x' -f2)
            local window_width=$(echo "$window_state" | grep WIDTH | cut -d'=' -f2)
            local window_height=$(echo "$window_state" | grep HEIGHT | cut -d'=' -f2)

            if [[ "$window_width" -ge "$screen_width" && "$window_height" -ge "$screen_height" ]]; then
                return 0
            fi
            ;;
        wmctrl)
            if wmctrl -l -G | grep -E "$(wmctrl -r :ACTIVE: -b | grep -Eo 'fullscreen')"; then
                return 0
            fi
            ;;
        xwininfo)
            local active_window_id=$(xprop -root _NET_ACTIVE_WINDOW | awk '{print $NF}')
            if [[ -n "$active_window_id" ]]; then
                local window_info=$(xwininfo -id "$active_window_id" 2>/dev/null)
                local screen_size=$(xdpyinfo | grep dimensions | awk '{print $2}')
                local screen_width=$(echo "$screen_size" | cut -d'x' -f1)
                local screen_height=$(echo "$screen_size" | cut -d'x' -f2)
                local window_width=$(echo "$window_info" | grep "Width:" | awk '{print $2}')
                local window_height=$(echo "$window_info" | grep "Height:" | awk '{print $2}')

                if [[ -n "$window_width" && -n "$window_height" && "$window_width" -ge "$screen_width" && "$window_height" -ge "$screen_height" ]]; then
                    return 0
                fi
            fi
            ;;
        *)
            return 1 # No tool available, assume not fullscreen
            ;;
    esac
    return 1
}

# Apply gamma settings to all connected displays
apply_gamma() {
    local gamma="$1"
    if [[ "$gamma" != "$CURRENT_GAMMA" ]]; then
        # Get all connected displays
        local display_array old_ifs
        old_ifs="$IFS"
        IFS=$'\n' read -d '' -r -a display_array < <(xrandr --current | grep " connected" | awk '{print $1}' | grep -v '^$' | sort -u) || true
        IFS="$old_ifs"

        if [[ ${#display_array[@]} -eq 0 ]]; then
            echo "Error: No connected displays found" | tee -a "$LOG_FILE"
            return 1
        fi

        # Apply gamma to each display
        for display in "${display_array[@]}"; do
            if [[ -n "$display" ]]; then
                if xrandr --output "$display" --gamma "$gamma" 2>>"$LOG_FILE"; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') - Applied gamma $gamma to $display" >> "$LOG_FILE"
                else
                    echo "$(date '+%Y-%m-%d %H:%M:%S') - Failed to apply gamma to $display" >> "$LOG_FILE"
                fi
            fi
        done
        CURRENT_GAMMA="$gamma"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Gamma unchanged: $gamma" >> "$LOG_FILE"
    fi
}

# Reset gamma to neutral on script interruption
reset_displays() {
    local displays
    IFS=$'\n' read -d '' -r -a displays < <(xrandr --current | grep " connected" | awk '{print $1}' | grep -v '^$' | sort -u) || true
    for display in "${displays[@]}"; do
        if [[ -n "$display" ]]; then
            xrandr --output "$display" --gamma "$NEUTRAL_GAMMA" 2>>"$LOG_FILE"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Reset gamma to $NEUTRAL_GAMMA on $display" >> "$LOG_FILE"
        fi
    done
}

# Main logic
main() {
    check_tools
    check_fullscreen_tool
    init_logging
    parse_args "$@"
    get_coordinates
    get_sunrise_sunset  # Ensure sunrise/sunset is checked on startup

    local last_weather_check=0
    local last_sun_check=$(date +%s)  # Initialize to current time
    local fullscreen_last_state=1

    while true; do
        # Check fullscreen every 3 seconds
        if is_fullscreen; then
            if [[ $fullscreen_last_state -ne 0 ]]; then
                apply_gamma "$NEUTRAL_GAMMA"
                fullscreen_last_state=0
            fi
            sleep 3
            continue
        else
            if [[ $fullscreen_last_state -eq 0 ]]; then
                fullscreen_last_state=1
            fi
        fi

        # Check sunrise/sunset every 10 minutes
        if [[ $(( $(date +%s) - last_sun_check )) -ge 600 ]]; then
            get_sunrise_sunset
            last_sun_check=$(date +%s)
        fi

        if is_daytime; then
            # Check weather every hour during day
            if [[ $(( $(date +%s) - last_weather_check )) -ge $WEATHER_TTL ]]; then
                get_weather
                last_weather_check=$(date +%s)
            fi

            if [[ "$WEATHER" == "Clear" ]]; then
                apply_gamma "$NEUTRAL_GAMMA"
            elif [[ "$WEATHER" == "unknown" ]]; then
                apply_gamma "$NEUTRAL_GAMMA" # Fallback to neutral
            else
                apply_gamma "$CLOUDY_GAMMA"
            fi
        else
            apply_gamma "$NIGHT_GAMMA"
        fi
        sleep 3
    done
}

trap 'reset_displays; exit 130' INT HUP TERM
main "$@"