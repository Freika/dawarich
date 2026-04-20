If you want to develop with dawarich you can use the devcontainer, with your IDE. It is tested with visual studio code.

Prerequisite :
```shell
Vscode with devcontainer extension
Git
Docker
```

**NOTE:** For Windows
Install a distro in WSL
```powershell
wsl --install
```
Install Git and clone from WSL command line :
```WSL
sudo apt update && sudo apt install git
git clone <repository-url>
```
Install WSL extension in VSCode


**NOTE:** On Apple Silicon (M1/M2/M3), `postgis/postgis:17-3.5-alpine` is not available due to architecture mismatch.
In `docker/docker-compose.yml`, replace it with `imresamu/postgis:17-3.5-alpine` before building the container.

Copy `.env.development.example` to `.env.development` (in the root project folder).

This ensures your `.env.development` is not synced to GitHub.

Load the directory in Vs-Code and press F1. And Run the command: `Dev Containers: Rebuild Containers` after a while you should see a terminal.

Afterwards you can run sidekiq:
```bash
bundle exec sidekiq
```

And in a second terminal the dawarich-app:
```bash
bundle exec bin/dev
```

You can connect with a web browser to http://127.0.0.l:3000/ and login with the default credentials.
