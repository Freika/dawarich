FROM openjdk:24-slim-bullseye

# Install pbzip2 for parallel extraction
RUN apt update && apt-get upgrade -y && \
    apt-get -y install wget bzip2 curl vim && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /photon
ADD https://github.com/komoot/photon/releases/download/0.6.0/photon-0.6.0.jar /photon/photon.jar
COPY entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh
VOLUME /photon/photon_data
EXPOSE 2322

ENTRYPOINT ["/photon/entrypoint.sh"]