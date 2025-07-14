# Installing dawarich with systemd

This guide is based on my experience setting up dawarich on Debian 12.

## Prerequisites

### Postgresql

You need a recent version of [Postgresql](https://www.postgresql.org/)
with [PostGIS](https://postgis.net/) support.

In Debian you can install it with
```sh
apt install postgresql-postgis
```

If you do not want to run the database on the same host as the
dawarich service, you need to reconfigure Postgresql to allow
connections from that host.

Dawarich will populate it's database itself and only needs a user
account to do so. This account needs to have superuser capabilities as
the database population includes enabling the postgis extention:
```sh
sudo -u postgres psql <<EOF
CREATE USER dawarich PASSWORD 'UseAStrongPasswordAndKeepItSecret';
ALTER USER dawarich WITH SUPERUSER;
EOF
```


### Redis

Install a recent version of [Redis](https://redis.io/).

In Debian you can install it with
```sh
apt install redis-server
```

If you do not want to run the redis service on the same host as the
dawarich service, you need to reconfigure redis to accept connection
from that host and most likely configure authentication.


### System User account

Create an account that will run the ruby services of dawarich. Of
course, you can choose another directory for it's HOME.

```sh
adduser --system --home /service/dawarich dawarich
```

### Ruby

Dawarich currently uses [Ruby](https://www.ruby-lang.org/) version
3.4.1 (yes, exactly this one). At least on Debian, this version is not
available at all in the package repositories. So I installed Ruby by
compiling from source:

```sh
apt install build-essential pkg-config libpq-dev libffi-dev libyaml-dev zlib1g-dev

# compile & install as unprivileged user
sudo -u dawarich bash

# download
cd ~
mkdir src
cd src
wget https://cache.ruby-lang.org/pub/ruby/3.4/ruby-3.4.1.tar.gz

# unpack
tar -xzf ruby-3.4.1.tar.gz
cd ~/ruby-3.4.1

# build & install
./configure --prefix $HOME/ruby-3.4.1
make all test install

# allow easy replacement of used ruby installation
ln -s ruby-3.4.1 ~dawarich/ruby

exit # sudo -u dawarich bash
```


## Install dawarich

0. Clone the repo to `/service/dawarich/dawarich` and install dependencies.
```sh
# install as unprivileged user
sudo -u dawarich bash

cd ~
git clone https://github.com/Freika/dawarich.git
cd dawarich

# install dependencies
bash systemd/install.sh

exit # sudo -u dawarich bash
```

0. Install, enable and start systemd services
```sh
# install systemd services
install systemd/dawarich.service systemd/dawarich-sidekiq.service /etc/systemd/system
systemctl daemon-reload
systemctl enable --now dawarich.service dawarich-sidekiq.service
systemctl status dawarich.service dawarich-sidekiq.service
```
