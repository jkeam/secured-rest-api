FROM docker.io/intersystemsdc/iris-community:2026.1-zpm

WORKDIR /home/irisowner/dev

## install git
USER root
COPY . /tmp/api
RUN cp /usr/irissys/dev/Container/waitReady.sh /tmp/api/waitReady.sh \
    touch /tmp/api/waitReady.log \
    chmod 777 /tmp/api/waitReady.sh \
    chmod 777 /tmp/api/waitReady.log

USER irisowner

RUN --mount=type=bind,src=.,dst=. \
    iris start IRIS && \
	iris session IRIS < /tmp/api/iris.script && \
    iris stop IRIS quietly
