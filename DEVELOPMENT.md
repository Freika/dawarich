If you want to develop with dawarich you can use the devcontainer, with your IDE. It is tested with visual studio code.

Prerequisite :
* Vscode
* devcontainer extension (in Vscode)
* Git
* Docker

**NOTE:** For Windows
Install the WSL Extension in vscode

Open powershell and install a distro in WSL
```powershell
wsl --install
```
Open Ubuntu from the start menu to open WSL cmd line then :
```WSL
sudo apt update && sudo apt install git
git clone <repository-url>
cd <YOUR_GIT_DIRECTORY>
code .
```

**NOTE:** On Apple Silicon (M1/M2/M3), `postgis/postgis:17-3.5-alpine` is not available due to architecture mismatch.
In `.devcontainer/docker-compose.yml`, replace it with `imresamu/postgis:17-3.5-alpine` before building the container.

Copy `.devcontainer/.env.example` to `.devcontainer/.env` 

This ensures your secret `.env` is not synced to GitHub.

Load the directory in Vs-Code and press F1. And Run the command:
```bash
 `Dev Containers: Rebuild Containers`
```

You can connect with a web browser to http://127.0.0.l:3000/ and login with the default credentials.