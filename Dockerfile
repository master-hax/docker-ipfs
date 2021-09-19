FROM ghcr.io/linuxserver/baseimage-alpine:3.13 as migration-bins

RUN \
  echo "**** install buid packages ****" && \
  apk add --no-cache \
    curl \
    git \
    go && \
  echo "**** build fs-repo-migrations ****" && \
  mkdir /bins && \
  IPFSMIG_VERSION=$(curl -sX GET "https://api.github.com/repos/ipfs/fs-repo-migrations/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]') && \
  git clone https://github.com/ipfs/fs-repo-migrations.git && \
  cd fs-repo-migrations && \
  git checkout ${IPFSMIG_VERSION} && \
  for BUILD in fs-repo-migrations fs-repo-9-to-10 fs-repo-10-to-11; do \
    cd ${BUILD} && \
    go build && \
    mv fs-repo-* /bins/ && \
    cd .. ; \
  done

FROM ghcr.io/linuxserver/baseimage-ubuntu:focal as ipfswebui

ARG IPFSWEB_VERSION

RUN \
  echo "**** install build packages ****" && \
    apt-get update && \
    apt-get install -y \
    curl \
    g++ \
    git \
    gnupg \
    make \
    python3-dev && \
  echo "**** install runtime *****" && \
  curl -s https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - && \
  echo 'deb https://deb.nodesource.com/node_14.x focal main' > /etc/apt/sources.list.d/nodesource.list && \
  apt-get update && \
  apt-get install -y \
    nodejs && \
  echo "**** build frontend ****" && \
  if [ -z ${IPFSWEB_VERSION+x} ]; then \
    IPFSWEB_VERSION=$(curl -sX GET "https://api.github.com/repos/ipfs/ipfs-webui/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]'); \
  fi && \
  curl -o \
    /tmp/ipfswebui.tar.gz -L \
    "https://github.com/ipfs/ipfs-webui/archive/refs/tags/${IPFSWEB_VERSION}.tar.gz" && \
  mkdir /ipfswebui && \
  tar xf \
    /tmp/ipfswebui.tar.gz -C \
    /ipfswebui --strip-components=1 && \
  cd /ipfswebui && \
  echo "**** npm ci ****" && \
  npm ci --prefer-offline --no-audit --progress=false && \
  echo "**** npm run build ****" && \
  npm run build && \
  echo "**** reduce layer size ****" && \
  apt-get -y purge \
    curl \
    g++ \
    git \
    gnupg \
    make \
    nodejs \
    python3-dev && \
  apt-get -y autoremove && \
  rm -rf \
    /tmp/* \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /ipfswebui/node_modules
 
FROM ghcr.io/linuxserver/baseimage-alpine:3.13

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# environment
ENV IPFS_PATH=/config/ipfs

RUN \
  echo "**** install runtime packages ****" && \
  apk add --no-cache \
    curl \
    logrotate \
    nginx \
    openssl \
    php7 \
    php7-fpm && \
  apk add --no-cache --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community \
    go-ipfs && \
  mkdir -p /var/www/html && \
  echo "**** configure nginx ****" && \
  echo 'fastcgi_param  SCRIPT_FILENAME $document_root$fastcgi_script_name;' >> \
    /etc/nginx/fastcgi_params && \
  rm -f /etc/nginx/conf.d/default.conf && \
  echo "**** fix logrotate ****" && \
  sed -i "s#/var/log/messages {}.*# #g" /etc/logrotate.conf && \
  sed -i 's#/usr/sbin/logrotate /etc/logrotate.conf#/usr/sbin/logrotate /etc/logrotate.conf -s /config/log/logrotate.status#g' \
    /etc/periodic/daily/logrotate && \
  echo "**** cleanup ****" && \
  rm -rf \
    /tmp/*

# copy files
COPY root/ /
COPY --from=migration-bins /bins /usr/bin
COPY --from=ipfswebui /ipfswebui/build/* /var/www/html/

# ports and volumes
EXPOSE 80 443 4001 5001 8080
VOLUME ["/config"]
