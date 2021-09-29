################################################################################
# Built with arch: amd64 flavor: xfce4 image: ubuntu:20.04
################################################################################
# base system
################################################################################

FROM ubuntu:20.04 as system

RUN sed -i 's#http://archive.ubuntu.com/ubuntu/#mirror://mirrors.ubuntu.com/mirrors.txt#' /etc/apt/sources.list;

# built-in packages
ENV DEBIAN_FRONTEND noninteractive
RUN apt update && apt -y dist-upgrade \
  && apt install -y --no-install-recommends --allow-unauthenticated software-properties-common curl apache2-utils \
  supervisor nginx sudo net-tools zenity xz-utils dbus-x11 x11-utils alsa-utils mesa-utils libgl1-mesa-dri openssh-client ca-certificates htop

# install debs error if combine together
RUN apt install -y --no-install-recommends --allow-unauthenticated xvfb x11vnc \
  vim-tiny firefox ttf-ubuntu-font-family ttf-wqy-zenhei \
  gtk2-engines-murrine \
  gnome-themes-standard \
  gtk2-engines-pixbuf \
  gtk2-engines-murrine \
  kmod \
  procps \
  less \
  multitail \
  zip \
  bash \
  bash-completion \
  binutils \
  file \
  iputils-ping \
  pavucontrol \
  pciutils \
  psmisc \
  fakeroot \
  fuse \
  wget \
  git \
  zsh \
  qterminal \
  apt-transport-https \
  software-properties-common

# VSCode
RUN wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg \
  && install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/ \
  && sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list' \
  && rm -f packages.microsoft.gpg
RUN apt update && apt -y install code

# PowerShell 7
RUN wget -q https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb \
  && dpkg -i packages-microsoft-prod.deb
RUN apt-get update && apt-get install -y powershell && rm packages-microsoft-prod.deb

# 

RUN apt install -y gpg-agent \
  && curl -LO https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
  && (dpkg -i ./google-chrome-stable_current_amd64.deb || apt-get install -fy) \
  && curl -sSL https://dl.google.com/linux/linux_signing_key.pub | apt-key add \
  && rm google-chrome-stable_current_amd64.deb

RUN apt install -y --no-install-recommends --allow-unauthenticated \
  xfce4 \
  arc-theme \
  xubuntu-desktop \
  xubuntu-artwork \
  xubuntu-default-settings \
  xserver-xorg-video-all \
  xserver-xorg-video-dummy \
  xfonts-cyrillic \
  xfonts-100dpi \
  xfonts-75dpi \
  mesa-utils-extra \
  xfonts-scalable \
  xorgxrdp \
  xfce4-appmenu-plugin \
  xfce4-datetime-plugin \
  xfce4-goodies \
  xfce4-terminal \
  xfce4-taskmanager \
  desktop-file-utils \
  fonts-dejavu \
  fonts-noto \
  fonts-noto-color-emoji \
  fonts-ubuntu \
  menu \
  menu-xdg \
  xdg-utils \
  xfce4-statusnotifier-plugin \
  xfce4-whiskermenu-plugin \
  xfonts-base \
  xfpanel-switch \
  xinput \
  xutils \
  xfonts-base \
  xterm

# tini to fix subreap
ARG TINI_VERSION=v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /bin/tini
RUN chmod +x /bin/tini

# ffmpeg
RUN apt update \
  && apt install -y --no-install-recommends --allow-unauthenticated \
      ffmpeg \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir /usr/local/ffmpeg \
  && ln -s /usr/bin/ffmpeg /usr/local/ffmpeg/ffmpeg

# python library
COPY rootfs/usr/local/lib/web/backend/requirements.txt /tmp/
RUN apt-get update \
  && dpkg-query -W -f='${Package}\n' > /tmp/a.txt \
  && apt-get install -y python3-pip python3-dev build-essential \
	&& pip3 install setuptools wheel && pip3 install -r /tmp/requirements.txt \
  && ln -s /usr/bin/python3 /usr/local/bin/python \
  && dpkg-query -W -f='${Package}\n' > /tmp/b.txt \
  && apt-get remove -y `diff --changed-group-format='%>' --unchanged-group-format='' /tmp/a.txt /tmp/b.txt | xargs` \
  && apt-get autoclean -y \
  && apt-get autoremove -y \
  && rm -rf /var/lib/apt/lists/* \
  && rm -rf /var/cache/apt/* /tmp/a.txt /tmp/b.txt


################################################################################
# builder
################################################################################
FROM ubuntu:20.04 as builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates gnupg patch

# nodejs
RUN curl -sL https://deb.nodesource.com/setup_16.x | bash - \
  && apt-get install -y nodejs

# yarn
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
  && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list \
  && apt-get update \
  && apt-get install -y yarn

# build frontend
COPY web /src/web
RUN cd /src/web \
  && yarn \
  && yarn build
RUN sed -i 's#app/locale/#novnc/app/locale/#' /src/web/dist/static/novnc/app/ui.js

################################################################################
# merge
################################################################################
FROM system
LABEL maintainer="Chris Bensch (chris.bensch@gmail.com)"

# Set the subject of the self-signed SSL-certificate
ARG KEYSUBJECT=/C=US/ST=Nevada/L=Las_Vegas/O=MyCorp/OU=MyOU/CN=CloudDesk

# Create self-signed certificate for noVNC.
RUN mkdir -p /etc/pki/tls/certs && openssl req -x509 -nodes -newkey rsa:4096 -days 3650 \
    -keyout /etc/pki/tls/certs/novnc.pem -out /etc/pki/tls/certs/novnc.pem  \
    -subj "${KEYSUBJECT}"


COPY --from=builder /src/web/dist/ /usr/local/lib/web/frontend/
COPY rootfs /
RUN ln -sf /usr/local/lib/web/frontend/static/websockify /usr/local/lib/web/frontend/static/novnc/utils/websockify && \
	chmod +x /usr/local/lib/web/frontend/static/websockify/run

RUN apt-get autoclean -y \
  && apt-get autoremove -y \
  && rm -rf /var/lib/apt/lists/*

# SSL Test
RUN mkdir -p /etc/nginx/ssl
COPY ssl/nginx.* /etc/nginx/ssl
# SSL Test

EXPOSE 80
WORKDIR /root
ENV HOME=/home/ubuntu \
    SHELL=/bin/bash
HEALTHCHECK --interval=30s --timeout=5s CMD curl --fail http://127.0.0.1:6079/api/health
ENTRYPOINT ["/startup.sh"]
