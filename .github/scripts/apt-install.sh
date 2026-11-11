#!/usr/bin/env bash
# Install apt packages on a GitHub runner, recovering from an unreachable Ubuntu mirror.
# Order: default mirror -> public DNS resolvers -> alternate mirror. Usage: apt-install.sh pkg [pkg...]
set -u
pkgs=("$@")

try_install() {
  timeout 150 sudo apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 update \
    && timeout 240 sudo apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 install -y "${pkgs[@]}"
}

echo "::group::network diagnostics"
cat /etc/resolv.conf || true
getent hosts azure.archive.ubuntu.com archive.ubuntu.com || echo "ubuntu mirrors do not resolve"
echo "::endgroup::"

echo "== attempt 1: default mirror"
try_install && exit 0

echo "== attempt 2: public DNS resolvers"
sudo mkdir -p /etc/systemd/resolved.conf.d
printf '[Resolve]\nDNS=1.1.1.1 8.8.8.8\nFallbackDNS=9.9.9.9\n' | sudo tee /etc/systemd/resolved.conf.d/ci-dns.conf >/dev/null
sudo systemctl restart systemd-resolved || true
sleep 3
getent hosts archive.ubuntu.com || echo "still does not resolve"
try_install && exit 0

echo "== attempt 3: alternate mirror"
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do
  [ -f "$f" ] || continue
  sudo sed -i -E 's#mirror\+file:/etc/apt/apt-mirrors.txt#http://mirrors.kernel.org/ubuntu#g; s#https?://([a-z]+\.)*archive\.ubuntu\.com/ubuntu/?#http://mirrors.kernel.org/ubuntu/#g; s#https?://security\.ubuntu\.com/ubuntu/?#http://mirrors.kernel.org/ubuntu/#g' "$f"
done
try_install && exit 0

echo "::error::could not install ${pkgs[*]} from any mirror"
exit 1
