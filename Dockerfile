FROM docker.io/intersystemsdc/iris-community:2026.1-zpm

WORKDIR /home/irisowner/dev

## install git
USER root
RUN apt update && apt-get -y install git
COPY . /tmp/api
USER irisowner

## Embedded Python environment

RUN --mount=type=bind,src=.,dst=. \
    iris start IRIS && \
	iris session IRIS < /tmp/api/iris.script && \
    iris stop IRIS quietly
