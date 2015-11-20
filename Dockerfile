FROM jeanblanchard/busybox-java:8

MAINTAINER brian.lininger@gmail.com

RUN \
	mkdir -p /opt/accounting-service/bin && \
	mkdir -p /opt/accounting-service/lib && \
	mkdir -p /opt/accounting-service/conf && \
	mkdir -p /opt/accounting-service/logs

COPY home /opt/accounting-service/

VOLUME /opt/accounting-service/conf
VOLUME /opt/accounting-service/logs

EXPOSE 8080 8081

CMD /opt/accounting-service/bin/start_service.sh
