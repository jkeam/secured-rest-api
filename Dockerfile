FROM docker.io/intersystemsdc/iris-community:2026.1-zpm

WORKDIR /home/irisowner/dev

USER root
COPY . /tmp/api
RUN touch /tmp/api/wait.log && \
    chmod 777 /tmp/api/wait.sh && \
    chmod 777 /tmp/api/wait.log \
    chown irisowner:irisowner /tmp/api/wait.sh \
    chown irisowner:irisowner /tmp/api/wait.log

RUN touch /usr/irissys/dev/Cloud/ICM/waitISC.log \
    chmod 777 /usr/irissys/dev/Cloud/ICM/waitISC.sh \
    chmod 777 /usr/irissys/dev/Cloud/ICM/waitISC.log \
    chown irisowner:irisowner /usr/irissys/dev/Cloud/ICM/waitISC.sh \
    chown irisowner:irisowner /usr/irissys/dev/Cloud/ICM/waitISC.log

USER irisowner

RUN --mount=type=bind,src=.,dst=. \
    iris start IRIS && \
	iris session IRIS < /tmp/api/iris.script && \
    iris stop IRIS quietly

CMD ["iris", "start", "IRIS"]
