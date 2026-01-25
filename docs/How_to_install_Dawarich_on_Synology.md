# How to install Dawarich on Synology using Docker

# Preparation

## Container manager
Firstly you need to install [Container manager](https://www.synology.com/en-global/dsm/feature/container-manager) on your DSM.

- Open Synology DSM web UI.
- In the main menu open **Package Center**.
- Search **Container Manager** in the "open source" section.
- Install that.

## Web station
Do the same for [Web station](https://www.synology.com/en-global/dsm/packages/WebStation) packet.

## Project folder preparation

### Docker root share
If you don't yet have separate share for docker projects would be good to create it.

If you don't want to use dedicated share for projects installed by docker skip it and go to the next chapter.

- Open **Control panel** -> **Shared folder** -> **Create** -> **Create shared folder**
- Set name, for example **docker**, and location.
- Check **Hide this shared folder in "My Network Places"**. This hides this folder from listening by smb, afp, ftp shares.
- Click **Next** several times until you see **Configure user permissions** window.
- Check **Read/write** access for your user and **No Access** for all another.

### Dawarich root folder
1. Open your [Docker root folder](#docker-root-share) in **File station**.
2. Create new folder **dawarich** and open it.
3. Create folders **app_storage**, **db_data**, **db_shared**, **public** and **redis** in **dawarich** folder.
4. Copy [docker compose](synology/docker-compose.yml) and [.env](synology/.env) files form **synology** repo folder into **dawarich** folder on your synology.

# Installation

## Project create
1. Open **Container Manager** -> **Projects** -> **Create**
2. In **create project window**.
   1. Set **project name** as you wish.
   2. Set **path** to [Dawarich root folder](#dawarich-root-folder).
      1. DSM asks about existed docker-compose file, choose **use existing a docker-compose.yml to create the project**.
   3. Click **Next**.
   4. Check **Set up web portal via Web Station**.
      1. Select container name, port, and **http** protocol (not https).
   5. Click "Next".
   6. Uncheck **Start the project once it is created**.
   7. Click "Done".
3. In the popup "dawarich has been created. Go to Web Station to configure the web portal for the container." click "OK". **Web station** Portal Creation Wizard will be opened.
4. Set **portal type** to  **Name-based**.
5. Set **hostname** as your wish. For example, if your DSM has hostname **my-syno.com**, you can use **dawarich.my-syno.com**.
6. Check **HTTPS settings - HSTS**
   >I expected that you have configured the certificate in DSM. See **Control panel** -> **Security** -> **Certificate**. For example, previously you configured **QuickConnect** or **DynDNS** (DDNS). See **Control panel** -> **External Access**
7. Click **Create**.

## Configuration
### DNS
On your local DNS server, you need to add new record with `dawarich.my-syno.com` and IP address of Synology (see **Control panel** -> **Network** -> **Network Interface** in your DSM) to provide correct access to Dawarich, or just use wildcard `*.my-syno.com` record to resolve all subdomains `my-syno.com` to Synology ip.

Please read the documentation of your DNS server to understand how to do it.

If you don't yet have a DNS server you can install [Synology DNS](https://www.synology.com/en-global/dsm/packages/DNSServer).
>Don't forget to reconfigure your DHCP server or all device settings in your local network to use this DNS server.

### Dawarich
1. Open /[Docker root folder](#docker-root-share)/[Dawarich root folder](#dawarich-root-folder)/.env file in any text editor. For example, you can use [Text editor](https://www.synology.com/en-global/dsm/packages/TextEditor) package or download it from **File station**, edit locally and upload it back, or get access by file share.
2. Update your `APPLICATION_HOSTS` value to include your **Dawarich hostname** that you set in **Web station**. In example above **dawarich.my-syno.com**. If you want to set multiple hosts, separate them by a comma: `dawarich.my-syno.com,dawarich2.my-syno.com`.
3. Set your current `TIME_ZONE`. The full list [here](https://github.com/Freika/dawarich/issues/27#issuecomment-2094721396).
4. Optionally change `DATABASE_USERNAME`, `DATABASE_USERNAME`, `DATABASE_NAME`.

5. Click on the name of your project.
6. Open **YAML Configurations** tab.

# Run
1. Open  **Container Manager** -> **Projects** ->**dawarich**
2. In the top right corner click **Action** -> **Build**
3. Wait until the popup writes that all is done and wait a few minutes more until all apps in containers start.
4. Open it by your hostname. In this example https://dawarich.my-syno.com

# Link in the Main menu
There are two possible options:
1. With **Web station**. But you will have the default web station icon.
2. With custom application for **Package Center**.
## Web station
- Open **Web station** -> **Web Portal** -> **dawarich (project)**.
- Check **Create shortcut on main menu** and set link name.

## Custom application
Synology allows you to create custom applications and install them by **Package Center**
[Here](https://github.com/vletroye/Mods) you can find a tool that creates dummy applications only with icon on the main menu.
You can use this tool and create your own app, or use the prepared one in this repo. But you need to change url to Dawarich inside it.

- Edit `update.sh` from `synology` folder. And in the first lines set correct values for `author` and `URL`.
- Run  `update.sh`. When the script finishes you will see the `spk` and `Dawarich.spk` in the same folder.

If you don't have Linux console you can create a temporal docker project to generate spk package.
- Create a new folder in [Docker root folder](#docker-root-share).
- Create subfolder `app` and  copy `update.sh` and `spk.tgz` into this subfolder.
- Open **Container Manager** -> **Projects** -> **Create**.
- Set any name, set a newly created folder, and set **Create docker-compose.yml**.
- Copy the text below to the text field.
```yaml
name: spk-template

services:
  spk-template:
    container_name: spk-template
    image: alpine
    restart: unless-stopped
    working_dir: /app
    volumes:
      - ./app:/app
    command:
      - /app/update.sh
```
- Click **Next**, **Next**, **Done**
The container should run and finish automatically.
- After that you can see `spk` and `Dawarich.spk` in the `app` folder.


- Check `url` in `spk/package/ui/config` file and `maintainer` and `distributor` in `spk/INFO` file.
- Open **Package Center**, click on **Manual Install**, select `Dawarich.spk`, agree with the security notice, and install it.
