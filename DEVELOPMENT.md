If you want to develop with dawarich you can use the devcontainer, with your IDE. It is tested with visual studio code.

**NOTE:** On Apple Silicon (M1/M2/M3), `postgis/postgis:17-3.5-alpine` is not available due to architecture mismatch.
In `.devcontainer/docker-compose.yml`, replace it with `imresamu/postgis:17-3.5-alpine` instead before building the container.

Load the directory in Vs-Code and press F1. And Run the command: `Dev Containers: Rebuild Containers` after a while you should see a terminal.

Copy .env.development.example to .env.development (in root project folder) 

This insure your .env.development are not synced to github

Afterwards you can run sidekiq:
```bash
bundle exec sidekiq
```

And in a second terminal the dawarich-app:
```bash
bundle exec bin/dev
```

You can connect with a web browser to http://127.0.0.l:3000/ and login with the default credentials.
