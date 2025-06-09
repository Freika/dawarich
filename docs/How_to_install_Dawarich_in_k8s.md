# How to install Dawarich on Kubernetes

> An **unofficial Helm chart** is available [here](https://github.com/Cogitri/charts/tree/master/charts/dawarich). For a manual installation using YAML manifests, see below.

## Prerequisites

- Kubernetes cluster and basic kubectl knowledge.
- Some persistent storage class prepared, in this example, Longhorn.
- Working Postgres and Redis instances. In this example Postgres lives in 'db' namespace and Redis in 'redis' namespace.
- Ngingx ingress controller with Letsencrypt integeation.
- This example uses 'example.com' as a domain name, you want to change it to your own.
- This will work on IPv4 and IPv6 Single Stack clusters, as well as Dual Stack deployments.

## Installation

### Namespace

```bash
kubectl create namespace dawarich
```

### Persistent volume claims

```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  namespace: dawarich
  name: public
  labels:
    storage.k8s.io/name: longhorn
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  namespace: dawarich
  name: watched
  labels:
    storage.k8s.io/name: longhorn
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
```

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dawarich
  namespace: dawarich
  labels:
    app: dawarich
spec:
  selector:
    matchLabels:
      app: dawarich
  template:
    metadata:
      labels:
        app: dawarich
    spec:
      containers:
        - name: dawarich
          env:
            - name: TIME_ZONE
              value: "Europe/Prague"
            - name: RAILS_ENV
              value: development
            - name: REDIS_URL
              value: redis://redis-master.redis.svc.cluster.local:6379/10
            - name: DATABASE_HOST
              value: postgres-postgresql.db.svc.cluster.local
            - name: DATABASE_PORT
              value: "5432"
            - name: DATABASE_USERNAME
              value: postgres
            - name: DATABASE_PASSWORD
              value: Password123!
            - name: DATABASE_NAME
              value: dawarich_development
            - name: MIN_MINUTES_SPENT_IN_CITY
              value: "60"
            - name: APPLICATION_HOST
              value: localhost
            - name: APPLICATION_HOSTS
              value: "dawarich.example.com, localhost"
            - name: APPLICATION_PROTOCOL
              value: http
            - name: PHOTON_API_HOST
              value: photon.komoot.io
            - name: PHOTON_API_USE_HTTPS
              value: "true"
            - name: RAILS_MIN_THREADS
              value: "5"
            - name: RAILS_MAX_THREADS
              value: "10"
          image: freikin/dawarich:0.16.4
          imagePullPolicy: Always
          volumeMounts:
            - mountPath: /var/app/public
              name: public
            - mountPath: /var/app/tmp/imports/watched
              name: watched
          command:
            - "web-entrypoint.sh"
          args:
            - "bin/rails server -p 3000 -b ::"
          resources:
            requests:
              memory: "1Gi"
              cpu: "250m"
            limits:
              memory: "3Gi"
              cpu: "2000m"
          ports:
          - containerPort: 3000
        - name: dawarich-sidekiq
          env:
            - name: RAILS_ENV
              value: development
            - name: REDIS_URL
              value: redis://redis-master.redis.svc.cluster.local:6379/10
            - name: DATABASE_HOST
              value: postgres-postgresql.db.svc.cluster.local
            - name: DATABASE_PORT
              value: "5432"
            - name: DATABASE_USERNAME
              value: postgres
            - name: DATABASE_PASSWORD
              value: Password123!
            - name: DATABASE_NAME
              value: dawarich_development
            - name: RAILS_MIN_THREADS
              value: "5"
            - name: RAILS_MAX_THREADS
              value: "10"
            - name: BACKGROUND_PROCESSING_CONCURRENCY
              value: "20"
            - name: APPLICATION_HOST
              value: localhost
            - name: APPLICATION_HOSTS
              value: "dawarich.example.com, localhost"
            - name: APPLICATION_PROTOCOL
              value: http
            - name: PHOTON_API_HOST
              value: photon.komoot.io
            - name: PHOTON_API_USE_HTTPS
              value: "true"
          image: freikin/dawarich:latest
          imagePullPolicy: Always
          volumeMounts:
            - mountPath: /var/app/public
              name: public
            - mountPath: /var/app/tmp/imports/watched
              name: watched
          command:
            - "sidekiq-entrypoint.sh"
          args:
            - "bundle exec sidekiq"
          resources:
            requests:
              memory: "1Gi"
              cpu: "250m"
            limits:
              memory: "3Gi"
              cpu: "1500m"
          livenessProbe:
            httpGet:
              path: /api/v1/health
              port: 3000
            initialDelaySeconds: 60
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /
              port: 3000
            initialDelaySeconds: 5
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
      volumes:
        - name: public
          persistentVolumeClaim:
            claimName: public
        - name: watched
          persistentVolumeClaim:
            claimName: watched
```

### Service and Ingress

```yaml
---
apiVersion: v1
kind: Service
metadata:
  namespace: dawarich
  labels:
    service: dawarich
  name: dawarich
spec:
  ports:
    - protocol: TCP
      port: 3000
      targetPort: 3000
  selector:
    app: dawarich
---
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  namespace: dawarich
  name: dawarich-ingress
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/proxy-body-size: 1000m
spec:
  tls:
    - hosts:
        - dawarich.example.com
      secretName: letsencrypt-prod
  rules:
    - host: dawarich.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: dawarich
                port:
                  number: 3000
```
