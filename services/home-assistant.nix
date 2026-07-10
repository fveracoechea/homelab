{config, lib, pkgs, ...}: {
  hardware.bluetooth.enable = true;

  services.home-assistant = {
    enable = true;
    openFirewall = false;
    configWritable = false;

    extraComponents = [
      "default_config"            # meta-component: enables the standard integration bundle (frontend, automation, integrations UI, onboarding, etc.)
      "met"                       # weather forecasts from the Norwegian Meteorological Institute
      "esphome"                   # ESP8266/ESP32 DIY smart devices flashed with ESPHome
      "sun"                       # sun position/elevation/times for automations (sunrise, sunset)
      "mobile_app"                # HA Companion app integration (iOS/Android notifications, location, sensors)
      "bluetooth"                 # BLE device discovery and communication
      "timer"                     # timer helpers for automations
      "local_file"                # serve local files (e.g. camera snapshots) from /var/lib/hass
      "local_todo"               # local to-do lists
      "local_calendar"           # local calendar for scheduling
      "generic_thermostat"        # virtual thermostat from a temperature sensor + heater switch
      "generic_hygrostat"         # virtual humidistat from a humidity sensor + humidifier switch
      "mold_indicator"            # mold risk sensor derived from temp + humidity
      "history_stats"             # aggregate statistics over historical state (e.g. "lights on for X hours today")
      "google_translate"          # free text-to-speech via Google Translate
      "radio_browser"             # internet radio station directory
      "profiler"                  # developer profiling/memory tools (disabled in production, available if needed)
      "ipp"                       # network printers via Internet Printing Protocol
      "tplink"                    # TP-Link Kasa smart plugs, switches, bulbs
      "tplink_tapo"               # TP-Link Tapo smart devices
      "wake_on_lan"               # turn on networked devices via Wake-on-LAN
    ];

    extraPackages = ps: with ps; [
      gtts                # Python lib for google_translate TTS
      radios              # Python lib for radio_browser
      pyswitchbot         # SwitchBot BLE devices
      ibeacon-ble         # iBeacon BLE proximity tracking
      govee-ble           # Govee BLE sensors and lights
      inkbird-ble         # Inkbird temp/humidity BLE sensors
      bthome-ble          # BThome open BLE protocol (shelly, DIY sensors)
      xiaomi-ble          # Xiaomi/Aqara BLE temperature/humidity/motion sensors
      qingping-ble        # Qingping BLE environmental monitors
      airthings-ble       # Airthings radon/air quality BLE monitors
      thermobeacon-ble    # Thermobeacon BLE temperature/humidity sensors
      thermopro-ble       # ThermoPro BLE sensors
      ruuvitag-ble        # RuuviTag BLE environmental beacons
      sensorpush-ble      # SensorPush BLE temp/humidity sensors
      sensirion-ble       # Sensirion BLE environmental sensors
    ];

    config = {
      default_config = {};
      http = {
        use_x_forwarded_for = true;
        trusted_proxies = ["127.0.0.1" "::1"];
      };
    };
  };

  systemd.services.home-assistant.serviceConfig = {
    AmbientCapabilities = ["CAP_NET_ADMIN" "CAP_NET_RAW"];
  };

  services.caddy.virtualHosts."home.veracoechea.com".extraConfig = ''
    tls /var/lib/acme/veracoechea.com/fullchain.pem /var/lib/acme/veracoechea.com/key.pem
    reverse_proxy 127.0.0.1:8123
  '';
}
