If you want to develop with dawarich you can use the devcontainer, with your IDE. It is tested with visual studio code.

Load the directory in Vs-Code and press F1. And Run the command: `Dev Containers: Rebuild Containers` after a while you should see a terminal.

Now you can create/prepare the Database (this need to be done once):
```bash
bundle exec rails db:create
bundle exec rails db:prepare
bundle exec rake data:migrate
bundle exec rake db:seed
```

Afterwards you can run sidekiq:
```bash
bundle exec sidekiq

```

And in a second terminal the dawarich-app:
```bash
bundle exec bin/dev
```

You can connect with a web browser to http://127.0.0.l:3000/ and login with the default credentials.
