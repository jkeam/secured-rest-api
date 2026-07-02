FROM docker.io/intersystemsdc/iris-community:2026.1-zpm

WORKDIR /home/irisowner/dev

USER root
COPY . /tmp/api

COPY --chown=irisowner --chmod=755 waitISC.sh /usr/irissys/dev/Cloud/ICM/
COPY --chown=irisowner --chmod=755 waitISC.log /usr/irissys/dev/Cloud/ICM/

USER irisowner

RUN --mount=type=bind,src=.,dst=. \
    iris start IRIS && \
	iris session IRIS < /tmp/api/iris.script && \
    iris stop IRIS quietly

CMD ["iris", "start", "IRIS"]
