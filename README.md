![Alt](https://repobeats.axiom.co/api/embed/4b0810273f8add2b2bb65098f840a29d66932b70.svg "Repobeats analytics image")

# 🚀 OpenNMS Quick Installer ✨

[![Integration Tests](https://github.com/opennms-forge/opennms-install/actions/workflows/integration-tests.yml/badge.svg)](https://github.com/opennms-forge/opennms-install/actions/workflows/integration-tests.yml)
[![Latest release](https://img.shields.io/github/v/release/opennms-forge/opennms-install)](https://github.com/opennms-forge/opennms-install/releases/latest)
[![License](https://img.shields.io/github/license/opennms-forge/opennms-install)](LICENSE)
[![OpenNMS Horizon](https://img.shields.io/badge/OpenNMS_Horizon-36.0.3-4c9d45)](https://docs.opennms.com/horizon/36/releasenotes/whatsnew.html)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-336791)](https://docs.opennms.com/horizon/36/deployment/core/system-requirements.html)

This script is a convenient bootstrap script to install OpenNMS on Debian or CentOS systems.
The script executes the steps documented in [Installation and Configuration guide](https://docs.opennms.com/horizon/latest/deployment/core/getting-started.html).

The scripts install a certified combination, shown in the badges above: the pinned OpenNMS Horizon and PostgreSQL versions are exactly what the CI matrix validates.
The certified combo is tested on, each on x86_64 and arm64:

* Ubuntu 24.04 (Noble Numbat)
* Debian 13 (Trixie)
* CentOS Stream 9/10
* Rocky Linux 9/10
* AlmaLinux 9/10

The OpenNMS package repositories ship arm64 builds of all native packages (jrrd2, jicmp, jicmp6), so the scripts work unmodified on both architectures; the CI matrix verifies every distro on both.

[![asciicast](https://asciinema.org/a/dCzY67dR6Ph07X2XLEdoGe9FC.svg)](https://asciinema.org/a/dCzY67dR6Ph07X2XLEdoGe9FC)

💁‍♀️ If you want to learn in detail, take a look at the deployment section in our documentation for [OpenNMS Horizon](https://docs.opennms.com/horizon/latest/) or [OpenNMS Meridian](https://docs.opennms.com/meridian/latest/).
We have also started to work on Ansible roles for the Ubuntu-based operating systems, which you can find at https://github.com/opennms-forge/ansible-opennms.

## 🎯 Scope

* Bootstrap a single-node OpenNMS system on RPM or DEB-based systems quickly with the certified stable release shown in the badges
* Installation procedure closely following the best practices from our official docs
* Scripts don't deal with existing installations or upgrades
* Scripts don't configure or install Minions, Sentinels, or distributed time series storage like Cortex.
* Users can use the installed system to learn and investigate how to configure OpenNMS Horizon in complex distributed environments, which gives them a quick starting point.

## 🏆 Goal

* Give people a way to install OpenNMS Horizon on their system to get familiar with OpenNMS Horizon quickly on a bare metal system.
* Remove the need to know Docker or Ansible to quickly bootstrap an OpenNMS Horizon system.
* Keep it simple and support operating systems based on official packages using RPM and DEB.

## 🕹️ Usage

Download the script for your distro family from the latest release and run it.

On an RPM-based system (AlmaLinux, Rocky Linux, CentOS Stream 9/10):

```bash
curl -fsSLO https://github.com/opennms-forge/opennms-install/releases/latest/download/bootstrap-yum.sh
sudo bash bootstrap-yum.sh
```

On a DEB-based system (Debian, Ubuntu):

```bash
curl -fsSLO https://github.com/opennms-forge/opennms-install/releases/latest/download/bootstrap-debian.sh
sudo bash bootstrap-debian.sh
```

Optionally, verify the download against the release checksums before running it:

```bash
curl -fsSLO https://github.com/opennms-forge/opennms-install/releases/latest/download/SHA256SUMS
sha256sum -c --ignore-missing SHA256SUMS
```

For full signature and provenance verification with cosign, see [Verifying artifacts](RELEASING.md#verifying-artifacts) in RELEASING.md.

## 👋 Say hello
You are very welcome to join us to make this repo a better place.
You can find us at:

* Public OpenNMS [Mattermost Chat](https://chat.opennms.com/opennms/channels/opennms-discussion)
* If you have longer discussions to share ideas, use our [OpenNMS Discourse](https://opennms.discourse.group) and tag your post with `opennms-installer`

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to contribute, [SUPPORT.md](SUPPORT.md) for where to ask questions, and [RELEASING.md](RELEASING.md) for how releases are cut.

## 📜 License

This project is licensed under the [GNU General Public License v3.0](LICENSE).
