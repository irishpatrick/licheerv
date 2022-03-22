#!/usr/bin/python3

import os
import pwinput
import subprocess
import sys

WPA_SUPPLICANT_CONF_TEMPLATE = \
"""

ctrl_interface=/run/wpa_supplicant
update_config=1
"""

INTERFACES_TEMPLATE = \
"""
source /etc/network/interfaces.d/*
allow-hotplug wlan0
iface wlan0 inet dhcp
	wpa-ssid {}
    wpa-psk {}
    #wpa-psk {}

"""

def main(argc, argv):
    print("Setup User")
    username = input("\tUsername: ")
    password = pwinput.pwinput(prompt="\tPassword: ")
    pwd_hash = ""

    print("Setup Wifi")
    wifi_ssid = input("\tSSID: ")
    wifi_tpsk = pwinput.pwinput(prompt="\tPassword: ")
    wifi_cfg = ""

    proc = subprocess.Popen(["openssl", "passwd", "-1", "-salt", username, password], stdout=subprocess.PIPE)
    (output, err) = proc.communicate()
    exit_code = proc.wait()
    pwd_hash = output.decode("utf-8")[:-1]

    proc = subprocess.Popen(["wpa_passphrase", wifi_ssid, wifi_tpsk], stdout=subprocess.PIPE)
    (output, err) = proc.communicate()
    exit_code = proc.wait()
    wifi_cfg = output.decode("utf-8")

    with open("config/wpa_supplicant.conf", "w") as fp:
        fp.write("{}\n{}".format(wifi_cfg, WPA_SUPPLICANT_CONF_TEMPLATE))

    with open("config/interfaces", "w") as fp:
        fp.write(INTERFACES_TEMPLATE.format(wifi_ssid, wifi_tpsk, ""))

    with open("config/buildcfg", "w") as fp:
        fp.write("export CFGUSERNAME=\'{}\'\nexport CFGUSERHASH=\'{}\'".format(username, pwd_hash))

if __name__ == "__main__":
    main(len(sys.argv), sys.argv)

