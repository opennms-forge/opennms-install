# 🚀 OpenNMS Quick install scripts ✨

This script is a convenient bootstrap script to install OpenNMS on Debian or CentOS systems.
The script executes the steps documented in [Installation and Configuration guide](https://docs.opennms.com/horizon/latest/deployment/core/getting-started.html).

The script is tested with:

* Ubuntu 22.04.2 (Jammy) x86_64
* Debian 12 (Bookworm) x86_64
* Rocky Linux 9.2 (Blue Onyx) x86_64
* AlmaLinux 8.8 (Sapphire Caracal) x86_64
* AlmaLinux 9.2 (Turquoise Kodkod) x86_64

[![asciicast](https://asciinema.org/a/dCzY67dR6Ph07X2XLEdoGe9FC.svg)](https://asciinema.org/a/dCzY67dR6Ph07X2XLEdoGe9FC)

## 🎯 Scope

* Bootstrap a single-node OpenNMS system on RPM or DEB based systems quickly with the latest stable release
* Installation procedure is close following the best-practices from our official docs
* Scripts don't deal with existing installations or upgrades
* Scripts doesn't configure or installs Minions, Sentinels or distributed time series storage like Cortex.
* Users can use the installed system to learn and investigate how to configure OpenNMS Horizon in complex distributed environments and gives them a quick starting point.

## 🏆 Goal

* Give people a way to install OpenNMS Horizon on their system to get familiar with OpenNMS Horizon quickly on a bare metal system.
* Remove the need to know Docker or Ansible to quickly boostrap a OpenNMS Horizon system.
* Keep it simple and support operating systems based on official packages using RPM and DEB.

## 🕹️ Usage

Download the script to your system.

Execute on a CentOS based system
```bash
sudo bash bootstrap-yum.sh
```

Execute on Debian-based system
```bash
sudo bash bootstrap-debian.sh
```

## 👋 Say hello
You are are very welcome to join us to make this repo a better place.
You can find us in:

* Public OpenNMS [Mattermost Chat](https://chat.opennms.com/opennms/channels/opennms-discussion)
* If you have longer discussions to share ideas use our [OpenNMS Discourse](https://opennms.discourse.group) and tag your post with `opennms-installer`
