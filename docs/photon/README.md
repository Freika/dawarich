# Own Photon instance deployment

The Dawarich utilises reverse geodata and a default Poton instance is [Komoot.oi](https://photon.komoot.io) that is throttled to 1 request per second. That makes decoding millions of records time consuming. The Dawarich can be configured to use your own Photon instance by setting the `PHOTON_URL` environment variable.

This folder contains Dockerfile and sample Kubernetes deployment. About 200Gb of persistenet storage is reqired.

##Building
```bash
docker build -t photon .
```
