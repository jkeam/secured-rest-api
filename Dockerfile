FROM docker.io/intersystemsdc/iris-community:2026.1-zpm

WORKDIR /home/irisowner/dev

## install git
USER root
COPY . /tmp/api
RUN touch /tmp/api/wait.log && \
    chmod 777 /tmp/api/wait.sh && \
    chmod 777 /tmp/api/wait.log

USER irisowner

RUN --mount=type=bind,src=.,dst=. \
    iris start IRIS && \
	iris session IRIS < /tmp/api/iris.script && \
    iris stop IRIS quietly
